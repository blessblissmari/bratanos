// BratanOS landing page — auto-detect OS + tab switching.

(function () {
  const ua = navigator.userAgent.toLowerCase();
  let os = "linux";
  if (ua.includes("mac"))           os = "mac";
  else if (ua.includes("windows"))  os = "windows";
  else if (ua.includes("linux") || ua.includes("x11")) os = "linux";

  // Pre-select the matching flash tab.
  const tabs   = document.querySelectorAll(".tab");
  const panels = document.querySelectorAll(".tab-panel");

  function activate(name) {
    tabs.forEach(t => t.classList.toggle("active", t.dataset.tab === name));
    panels.forEach(p => p.classList.toggle("hidden", p.dataset.panel !== name));
  }
  tabs.forEach(t => t.addEventListener("click", () => activate(t.dataset.tab)));
  activate(os);

  // Highlight the matching download card.
  document.querySelectorAll(".download-card").forEach(card => {
    if (card.dataset.os === os) {
      card.style.borderColor = "var(--accent)";
      card.style.boxShadow   = "inset 0 0 0 1px var(--accent)";
    }
  });
})();
