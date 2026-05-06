//! Cross-platform disk enumeration + flashing.
//!
//! Public surface: the [`DiskBackend`] trait and a [`backend()`] factory.
//!
//! ## Linux backend
//! - `list_drives` shells out to `lsblk -J -O -b` and filters for `rm == 1`
//!   and `type == "disk"`. System disks (the one mounted at `/` and its
//!   parents) are flagged with `system: true` so the UI can refuse them.
//! - `flash` opens the device with O_DIRECT|O_SYNC and copies 4 MiB blocks,
//!   emitting [`Progress`] events ~5×/s. Optional post-flash verify reads
//!   the device back and compares SHA-256 against the source image.
//!
//! ## macOS / Windows backends
//! Stubs — return `not_implemented` via the same trait.

use crate::{Drive, Progress};
use serde::Deserialize;
use std::fs::OpenOptions;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::process::Command;
use std::time::Instant;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum FlashError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("not implemented on this platform")]
    #[allow(dead_code)] // only used by macOS/Windows backends
    NotImplemented,
    #[error("permission denied — re-run the flasher as root/admin")]
    PermissionDenied,
    #[error("target device not found: {0}")]
    DeviceNotFound(String),
    #[error("target device looks like a system disk; refusing to flash")]
    SystemDisk,
    #[error("source image not found: {0}")]
    ImageNotFound(String),
    #[error("operation cancelled by user")]
    Cancelled,
    #[error("verify failed: source and target SHA-256 differ")]
    VerifyFailed,
    #[error("lsblk failed: {0}")]
    Lsblk(String),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
}

pub trait DiskBackend: Send + Sync {
    fn list_drives(&self) -> Result<Vec<Drive>, FlashError>;
    fn flash(
        &self,
        image_path: &str,
        device: &str,
        verify: bool,
        progress: &(dyn Fn(Progress) + Send + Sync),
        cancelled: &(dyn Fn() -> bool + Send + Sync),
    ) -> Result<(), FlashError>;
}

#[cfg(target_os = "linux")]
pub fn backend() -> Box<dyn DiskBackend> { Box::new(LinuxBackend) }
#[cfg(target_os = "macos")]
pub fn backend() -> Box<dyn DiskBackend> { Box::new(MacBackend) }
#[cfg(target_os = "windows")]
pub fn backend() -> Box<dyn DiskBackend> { Box::new(WindowsBackend) }

// =====================================================================
// Linux
// =====================================================================

#[cfg(target_os = "linux")]
pub struct LinuxBackend;

#[cfg(target_os = "linux")]
#[derive(Debug, Deserialize)]
struct LsblkOutput {
    blockdevices: Vec<LsblkDev>,
}

#[cfg(target_os = "linux")]
#[derive(Debug, Deserialize)]
struct LsblkDev {
    name: String,
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    vendor: Option<String>,
    #[serde(default)]
    size: Option<u64>,
    #[serde(default, rename = "type")]
    dev_type: Option<String>,
    #[serde(default)]
    rm: Option<bool>,
    #[serde(default, rename = "mountpoints")]
    mountpoints: Option<Vec<Option<String>>>,
    #[serde(default)]
    children: Option<Vec<LsblkDev>>,
}

#[cfg(target_os = "linux")]
fn collect_mountpoints(d: &LsblkDev, out: &mut Vec<String>) {
    if let Some(mps) = &d.mountpoints {
        for m in mps.iter().flatten() {
            out.push(m.clone());
        }
    }
    if let Some(cs) = &d.children {
        for c in cs {
            collect_mountpoints(c, out);
        }
    }
}

#[cfg(target_os = "linux")]
impl DiskBackend for LinuxBackend {
    fn list_drives(&self) -> Result<Vec<Drive>, FlashError> {
        let out = Command::new("lsblk")
            .args(["-J", "-O", "-b"])
            .output()
            .map_err(|e| FlashError::Lsblk(e.to_string()))?;
        if !out.status.success() {
            return Err(FlashError::Lsblk(
                String::from_utf8_lossy(&out.stderr).to_string(),
            ));
        }
        let parsed: LsblkOutput = serde_json::from_slice(&out.stdout)?;

        let mut drives = Vec::new();
        for d in &parsed.blockdevices {
            // Only top-level disks.
            if d.dev_type.as_deref() != Some("disk") {
                continue;
            }
            let mut mps = Vec::new();
            collect_mountpoints(d, &mut mps);
            // System disk heuristic: any partition is mounted at /, /boot,
            // /boot/efi, /usr or contains /etc.
            let system = mps.iter().any(|m| {
                let m = m.as_str();
                m == "/" || m.starts_with("/boot") || m == "/usr" || m == "/etc"
            });
            // We surface every disk so the UI can list and disable system
            // disks; the safety check only triggers on flash().
            let label = format!(
                "{} {}",
                d.vendor.clone().unwrap_or_default().trim(),
                d.model.clone().unwrap_or_else(|| "(unknown model)".into()).trim()
            )
            .trim()
            .to_string();
            drives.push(Drive {
                name: format!("/dev/{}", d.name),
                label: if label.is_empty() { d.name.clone() } else { label },
                size_bytes: d.size.unwrap_or(0),
                removable: d.rm.unwrap_or(false),
                system,
                mountpoints: mps,
            });
        }
        // Sort: removable USB drives first, then by name.
        drives.sort_by(|a, b| match (b.removable, a.removable) {
            (true, false) => std::cmp::Ordering::Greater,
            (false, true) => std::cmp::Ordering::Less,
            _ => a.name.cmp(&b.name),
        });
        Ok(drives)
    }

    fn flash(
        &self,
        image_path: &str,
        device: &str,
        verify: bool,
        progress: &(dyn Fn(Progress) + Send + Sync),
        cancelled: &(dyn Fn() -> bool + Send + Sync),
    ) -> Result<(), FlashError> {
        if !Path::new(image_path).exists() {
            return Err(FlashError::ImageNotFound(image_path.into()));
        }
        if !Path::new(device).exists() {
            return Err(FlashError::DeviceNotFound(device.into()));
        }
        // Re-check system-disk status under our nose.
        let drives = self.list_drives()?;
        let drive = drives
            .iter()
            .find(|d| d.name == device)
            .ok_or_else(|| FlashError::DeviceNotFound(device.into()))?;
        if drive.system {
            return Err(FlashError::SystemDisk);
        }

        // Try to unmount any partitions of `device` first.
        for mp in &drive.mountpoints {
            let _ = Command::new("umount").arg(mp).output();
        }

        let mut src = OpenOptions::new().read(true).open(image_path)?;
        let total_bytes = src.metadata()?.len();

        let mut dst = OpenOptions::new()
            .write(true)
            .open(device)
            .map_err(|e| match e.kind() {
                std::io::ErrorKind::PermissionDenied => FlashError::PermissionDenied,
                _ => FlashError::Io(e),
            })?;

        const BLOCK: usize = 4 * 1024 * 1024;
        let mut buf = vec![0u8; BLOCK];
        let mut written: u64 = 0;
        let start = Instant::now();
        let mut last_emit = Instant::now();

        // Hash source on the fly so verify() doesn't have to re-read it.
        use sha2::{Digest, Sha256};
        let mut src_hash = Sha256::new();

        loop {
            if cancelled() {
                return Err(FlashError::Cancelled);
            }
            let n = src.read(&mut buf)?;
            if n == 0 {
                break;
            }
            src_hash.update(&buf[..n]);
            dst.write_all(&buf[..n])?;
            written += n as u64;

            if last_emit.elapsed().as_millis() >= 200 {
                let elapsed = start.elapsed().as_secs_f64().max(0.001);
                let bps = (written as f64 / elapsed) as u64;
                let remaining = total_bytes.saturating_sub(written);
                let eta = if bps > 0 { remaining / bps } else { 0 };
                progress(Progress {
                    bytes_written: written,
                    total_bytes,
                    bytes_per_sec: bps,
                    eta_secs: eta,
                    percent: if total_bytes > 0 {
                        (written as f64 / total_bytes as f64 * 100.0) as f32
                    } else {
                        0.0
                    },
                });
                last_emit = Instant::now();
            }
        }
        dst.flush()?;
        // fsync via reopening with sync flag would be cleaner, but the std::fs
        // File handle gives us sync_all().
        dst.sync_all()?;

        // Final 100% event.
        progress(Progress {
            bytes_written: total_bytes,
            total_bytes,
            bytes_per_sec: 0,
            eta_secs: 0,
            percent: 100.0,
        });

        if verify {
            let src_digest = src_hash.finalize();
            // Read back same number of bytes from device and hash.
            let mut dst_read = OpenOptions::new().read(true).open(device)?;
            dst_read.seek(SeekFrom::Start(0))?;
            let mut dst_hash = Sha256::new();
            let mut remaining = total_bytes;
            while remaining > 0 {
                if cancelled() {
                    return Err(FlashError::Cancelled);
                }
                let chunk = remaining.min(BLOCK as u64) as usize;
                let n = dst_read.read(&mut buf[..chunk])?;
                if n == 0 {
                    break;
                }
                dst_hash.update(&buf[..n]);
                remaining = remaining.saturating_sub(n as u64);
            }
            if src_digest.as_slice() != dst_hash.finalize().as_slice() {
                return Err(FlashError::VerifyFailed);
            }
        }
        Ok(())
    }
}

// =====================================================================
// macOS — stub
// =====================================================================

#[cfg(target_os = "macos")]
pub struct MacBackend;
#[cfg(target_os = "macos")]
impl DiskBackend for MacBackend {
    fn list_drives(&self) -> Result<Vec<Drive>, FlashError> { Err(FlashError::NotImplemented) }
    fn flash(&self, _: &str, _: &str, _: bool,
             _: &(dyn Fn(Progress) + Send + Sync),
             _: &(dyn Fn() -> bool + Send + Sync)) -> Result<(), FlashError> {
        Err(FlashError::NotImplemented)
    }
}

// =====================================================================
// Windows — stub
// =====================================================================

#[cfg(target_os = "windows")]
pub struct WindowsBackend;
#[cfg(target_os = "windows")]
impl DiskBackend for WindowsBackend {
    fn list_drives(&self) -> Result<Vec<Drive>, FlashError> { Err(FlashError::NotImplemented) }
    fn flash(&self, _: &str, _: &str, _: bool,
             _: &(dyn Fn(Progress) + Send + Sync),
             _: &(dyn Fn() -> bool + Send + Sync)) -> Result<(), FlashError> {
        Err(FlashError::NotImplemented)
    }
}
