//! BratanOS Flasher — Tauri app entry point.
//!
//! Frontend commands:
//!   list_drives()         -> Vec<Drive>     removable USB devices
//!   am_i_root()           -> bool           Linux only; warns if not root
//!   flash(image, device)  -> ()             writes blocks + emits `flash:progress`
//!   cancel_flash()        -> ()             flips the cancel flag
//!
//! Linux fully implemented. macOS/Windows scaffolded but return
//! "not implemented" via the same `DiskBackend` trait.

mod disk;

use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Emitter, Manager, State};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Drive {
    pub name: String,        // e.g. /dev/sdb
    pub label: String,       // "Kingston DataTraveler 32GB"
    pub size_bytes: u64,
    pub removable: bool,
    pub system: bool,        // true if this looks like a system disk
    pub mountpoints: Vec<String>,
}

#[derive(Debug, Serialize, Clone)]
pub struct Progress {
    pub bytes_written: u64,
    pub total_bytes: u64,
    pub bytes_per_sec: u64,
    pub eta_secs: u64,
    pub percent: f32,
}

#[derive(Default)]
struct AppState {
    cancel: Arc<AtomicBool>,
}

#[tauri::command]
fn list_drives() -> Result<Vec<Drive>, String> {
    disk::backend().list_drives().map_err(|e| e.to_string())
}

#[tauri::command]
fn cancel_flash(state: State<'_, AppState>) {
    state.cancel.store(true, Ordering::SeqCst);
}

#[tauri::command]
async fn flash(
    app: AppHandle,
    state: State<'_, AppState>,
    image_path: String,
    device: String,
    verify: bool,
) -> Result<(), String> {
    let cancel = state.cancel.clone();
    cancel.store(false, Ordering::SeqCst);

    let app_for_progress = app.clone();
    let cb = move |p: Progress| {
        let _ = app_for_progress.emit("flash:progress", &p);
    };
    let cancel_for_check = cancel.clone();
    let cancel_fn = move || cancel_for_check.load(Ordering::SeqCst);

    let res = tokio::task::spawn_blocking(move || {
        disk::backend().flash(&image_path, &device, verify, &cb, &cancel_fn)
    })
    .await
    .map_err(|e| format!("worker join: {e}"))?;

    match res {
        Ok(_) => {
            let _ = app.emit("flash:done", serde_json::json!({"ok": true}));
            Ok(())
        }
        Err(e) => {
            let msg = e.to_string();
            let _ = app.emit("flash:done", serde_json::json!({"ok": false, "error": msg.clone()}));
            Err(msg)
        }
    }
}

#[tauri::command]
fn am_i_root() -> bool {
    #[cfg(unix)]
    {
        // SAFETY: geteuid is always safe.
        unsafe { libc_geteuid() == 0 }
    }
    #[cfg(not(unix))]
    { false }
}

#[cfg(unix)]
extern "C" {
    #[link_name = "geteuid"]
    fn libc_geteuid() -> u32;
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            list_drives,
            flash,
            cancel_flash,
            am_i_root,
        ])
        .setup(|app| {
            #[cfg(debug_assertions)]
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.open_devtools();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running BratanOS Flasher");
}
