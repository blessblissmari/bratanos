// BratanOS Flasher — frontend logic.
//
// This module is small and intentionally framework-free: just the Tauri
// JS API + DOM. Three pieces of state:
//   - selectedImage: absolute path to the chosen ISO
//   - selectedDrive: /dev/sdX of the chosen target
//   - flashing:      boolean, true while a flash is in progress
//
// Buttons enable/disable themselves based on the trio.

import { invoke } from "https://esm.sh/@tauri-apps/api@2/core";
import { open as pickFile } from "https://esm.sh/@tauri-apps/plugin-dialog@2";
import { listen } from "https://esm.sh/@tauri-apps/api@2/event";

const $ = (id) => document.getElementById(id);

const state = {
  image: null,        // string | null
  drive: null,        // Drive   | null
  flashing: false,
};

// ---------- helpers ----------

function fmtBytes(n) {
  if (!Number.isFinite(n) || n <= 0) return "0 B";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return `${n.toFixed(n < 10 && i > 0 ? 1 : 0)} ${u[i]}`;
}

function fmtEta(secs) {
  if (!Number.isFinite(secs) || secs <= 0) return "--:--";
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = Math.floor(secs % 60);
  if (h > 0) return `${h}h${m.toString().padStart(2, "0")}m`;
  return `${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
}

function setStatus(text, kind) {
  const el = $("status");
  el.textContent = text;
  el.className = `status ${kind || "muted"}`;
}

function refreshFlashButton() {
  $("btn-flash").disabled = !(state.image && state.drive && !state.drive.system && !state.flashing);
}

// ---------- step 1: pick image ----------

$("btn-pick-image").addEventListener("click", async () => {
  const path = await pickFile({
    multiple: false,
    title: "Select a BratanOS ISO",
    filters: [{ name: "Disk images", extensions: ["iso", "img"] }],
  });
  if (!path) return;
  state.image = path;
  $("image-summary").textContent = path;
  $("image-summary").classList.remove("muted");
  refreshFlashButton();
});

// ---------- step 2: drive list ----------

async function loadDrives() {
  const drives = await invoke("list_drives");
  const list = $("drive-list");
  list.innerHTML = "";
  $("drive-count").textContent = `${drives.length} disk(s) found`;
  for (const d of drives) {
    const li = document.createElement("li");
    li.className = "drive" + (d.system ? " drive--system" : "");
    li.innerHTML = `
      <div class="drive__icon">${d.removable ? "💾" : "🗄️"}</div>
      <div>
        <div class="drive__name">${d.name}</div>
        <div class="muted">${d.label || "(unknown)"}</div>
      </div>
      <div class="drive__size">${fmtBytes(d.size_bytes)}</div>
      <div>
        ${d.system ? '<span class="drive__tag drive__tag--system">SYSTEM</span>' :
          d.removable ? '<span class="drive__tag drive__tag--rm">USB</span>' :
          '<span class="drive__tag">internal</span>'}
      </div>
    `;
    if (!d.system) {
      li.addEventListener("click", () => {
        if (state.flashing) return;
        document.querySelectorAll(".drive--selected").forEach(n => n.classList.remove("drive--selected"));
        li.classList.add("drive--selected");
        state.drive = d;
        refreshFlashButton();
        setStatus(`Will flash ${d.name} (${fmtBytes(d.size_bytes)})`);
      });
    }
    list.appendChild(li);
  }
}
$("btn-refresh").addEventListener("click", loadDrives);

// ---------- step 3: flash ----------

$("btn-flash").addEventListener("click", async () => {
  if (!state.image || !state.drive) return;
  const verify = $("opt-verify").checked;
  const ok = confirm(
    `This will ERASE EVERYTHING on ${state.drive.name} (${fmtBytes(state.drive.size_bytes)})\n` +
    `and write ${state.image}.\n\nProceed?`
  );
  if (!ok) return;

  state.flashing = true;
  refreshFlashButton();
  $("btn-cancel").classList.remove("hidden");
  $("progress-card").classList.remove("hidden");
  setStatus("Flashing…");

  try {
    await invoke("flash", { imagePath: state.image, device: state.drive.name, verify });
  } catch (e) {
    setStatus(`error: ${e}`, "muted");
  } finally {
    state.flashing = false;
    $("btn-cancel").classList.add("hidden");
    refreshFlashButton();
  }
});

$("btn-cancel").addEventListener("click", () => invoke("cancel_flash"));

await listen("flash:progress", (ev) => {
  const p = ev.payload;
  $("progress-fill").style.width = p.percent.toFixed(2) + "%";
  $("metric-percent").textContent = p.percent.toFixed(1) + "%";
  $("metric-speed").textContent   = fmtBytes(p.bytes_per_sec) + "/s";
  $("metric-eta").textContent     = fmtEta(p.eta_secs);
  $("metric-bytes").textContent   = `${fmtBytes(p.bytes_written)} / ${fmtBytes(p.total_bytes)}`;
});

await listen("flash:done", (ev) => {
  const r = ev.payload;
  if (r.ok) setStatus("✓ done — eject and boot from USB", "muted");
  else setStatus(`✗ failed: ${r.error}`, "muted");
});

// ---------- boot ----------

(async function init() {
  try {
    const root = await invoke("am_i_root");
    if (!root) $("root-warning").classList.remove("hidden");
  } catch { /* non-unix */ }
  await loadDrives();
})();
