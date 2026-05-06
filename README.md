# BratanOS

> Arch Linux + i3wm with the discipline of NixOS — minus the complexity.

**Site:** https://blessblissmari.github.io/bratanos/
**Latest ISO:** [bratanos-2026.05.06-x86_64.iso](https://github.com/blessblissmari/bratanos/releases/download/v0.1.0/bratanos-2026.05.06-x86_64.iso) (1.5 GB hybrid)

BratanOS keeps everything that makes Arch elegant (`pacman`, rolling
release, the wiki) and bolts on the one thing it lacks: **automatic
cleanup**. Orphan packages, stale caches, old kernels and `~/.cache`
gunk never accumulate, because tidy logic is wired into pacman itself.

It also ships with a balenaEtcher-style **flasher** so you don't have
to teach yourself `dd` to install it.

## What's in the box

| Component | What it is |
|-----------|-----------|
| `archiso/` | Build profile for the bootable, hybrid (USB-flashable) ISO. |
| `src/bratan-tidy/` | Cleanup CLI: orphans, cache, kernels, journal, `.pacnew`/`.pacsave`, broken symlinks. |
| `src/bratan-pacman/` | `pacman` wrapper that transparently falls back to AUR via `paru` for missing packages. |
| `src/bratan-grub/` | GRUB theme installer (`bratanos-grub-install`). |
| `installer/` | Tauri (Rust + web) desktop flasher app. balenaEtcher-style. |
| `web/` | Static landing/download site. |
| `Dockerfile` | Reproducible ISO builder for non-Arch hosts. |
| `Makefile` | `make iso`, `make iso-docker`, `make qemu`, `make stage`, `make lint`. |

## Quick start — try it without installing

```sh
# build the ISO (needs Arch host, or use Docker — see below)
make iso

# write the ISO to a USB stick (Linux):
sudo dd if=out/bratanos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
sudo sync
```

Don't have Arch handy? Use Docker:

```sh
make iso-docker     # builds inside an archlinux:latest container
```

Test the ISO in QEMU/UEFI:

```sh
make qemu
```

On macOS/Windows, the same ISO works with [balenaEtcher],
[Rufus] (DD mode) or [Ventoy].

## The tidy system, end-to-end

Three layers of cleanup, all using just `pacman` + `systemd` — **no new
package manager**.

1. **`bratan-tidy`** — the CLI you'll actually run.
   ```sh
   bratan-tidy --status            # what's reclaimable
   sudo bratan-tidy --apply        # actually clean
   sudo bratan-tidy --apply cache  # only trim pacman cache
   ```

2. **Pacman hook** — runs `bratan-tidy --auto orphans cache` after
   every `pacman -R`. So `pacman -Rns thunderbird` doesn't leave
   `firefox-i18n-foo` behind as an orphan.

3. **Weekly timer** — `bratan-tidy.timer` runs the same job every
   week (idle IO, AC-power-only), so even an idle machine stays clean.

What gets cleaned (default tasks):
- **orphans** — `pacman -Rns $(pacman -Qtdq)` until none remain
- **cache** — `paccache -rk2 && paccache -ruk0` (last 2 versions per pkg, drop uninstalled)
- **kernels** — stale `/usr/lib/modules/<ver>` dirs from removed kernels
- **pacfiles** — surfaces `.pacnew`/`.pacsave`, optional `pacdiff` merge
- **userconfigs** — informational scan of `~/.config`, `~/.cache`, `~/.local/share` for orphan dirs (never deleted automatically)
- **journal** — `journalctl --vacuum-time=14d`
- **symlinks** — broken symlinks under `/etc` and `$HOME`

Tunable via `/etc/bratanos/tidy.conf`.

## AUR via plain `pacman`

`/usr/local/bin/pacman` is a thin wrapper that:

- delegates to real `pacman` for everything that already works
- if `pacman -S <pkg>` fails with "target not found", transparently
  retries via `paru`
- runs `bratan-tidy --auto` after every removal

```sh
sudo pacman -S brave-bin       # comes from Chaotic-AUR (prebuilt binary)
sudo pacman -S obscure-aur-thing   # paru builds it from AUR — automatic
```

[Chaotic-AUR] is enabled out of the box on first boot via the
`bratanos-firstboot.service` unit, so most popular AUR packages
arrive as prebuilt binaries (no compilation).

## GRUB theme + ly greeter

- A BratanOS-branded GRUB theme is installed by `bratanos-grub-install`
  (`/usr/share/grub/themes/bratanos`). It generates a wallpaper via
  ImageMagick, sets `GRUB_THEME` in `/etc/default/grub`, and runs
  `grub-mkconfig`.
- [ly] is the default display manager. Themed at `/etc/ly/config.ini`
  with a Catppuccin-ish palette and pre-selected i3 session.

## BratanOS Flasher (Tauri app)

A balenaEtcher-style installer for BratanOS itself.

- **Frontend** (`installer/ui/`): plain HTML/CSS/JS, no framework.
- **Backend** (`installer/src-tauri/`): Rust + Tauri 2.
  - `list_drives` — JSON parse of `lsblk -J -O -b`, system-disk detection.
  - `flash` — 4 MiB block writes, optional SHA-256 verify, progress events.
  - `cancel_flash`, `am_i_root`.
- **Linux** is fully implemented and works today.
- **macOS / Windows** backends are scaffolded behind the same
  `DiskBackend` trait — straightforward to fill in.

Build it:

```sh
cd installer
cargo install tauri-cli --version '^2'
cargo tauri dev      # development mode
cargo tauri build    # ship a deb / AppImage
sudo target/release/bratan-flasher
```

System dependencies for building on Debian/Ubuntu:

```sh
sudo apt install pkg-config libglib2.0-dev libgtk-3-dev \
    libwebkit2gtk-4.1-dev libsoup-3.0-dev libjavascriptcoregtk-4.1-dev \
    libssl-dev librsvg2-dev libxdo-dev
```

## Repo layout

```
.
├── Makefile                 # build orchestration
├── Dockerfile               # arch-builder for non-arch hosts
├── README.md
├── archiso/                 # ISO build profile (mkarchiso input)
│   ├── profiledef.sh
│   ├── packages.x86_64
│   ├── pacman.conf
│   ├── grub/grub.cfg        # EFI loader on the live ISO
│   ├── syslinux/syslinux.cfg
│   └── airootfs/            # filesystem overlay copied into the ISO
├── src/
│   ├── bratan-tidy/         # CLI + man page + tidy.conf
│   ├── bratan-pacman/       # pacman wrapper + paru.conf + PATH snippet
│   └── bratan-grub/         # bratanos-grub-install
├── installer/               # Tauri-based flasher app
│   ├── src-tauri/           # Rust backend
│   └── ui/                  # HTML/CSS/JS frontend
├── web/                     # static landing page
└── docs/
```

## Status

This is v0.1 — the foundation. Working today:

- [x] `bratan-tidy` (full)
- [x] `bratan-pacman` (full, Linux)
- [x] systemd timer + pacman hook
- [x] Chaotic-AUR + paru bootstrap
- [x] archiso profile (BIOS + UEFI boot)
- [x] GRUB theme installer
- [x] ly greeter config
- [x] Tauri flasher — Linux backend (full)
- [x] Tauri flasher — macOS/Windows scaffolds
- [x] Static landing/download site

Future work:

- [ ] Custom `bratanos-installer` TUI on top of `archinstall`
- [ ] First-class secure-boot signing
- [ ] BratanOS pacman repo (signed `bratan-tidy` + `bratan-pacman` packages)
- [ ] Tauri flasher: macOS + Windows backends

## License

MIT — see [LICENSE](./LICENSE).

[balenaEtcher]: https://etcher.balena.io/
[Rufus]: https://rufus.ie/
[Ventoy]: https://www.ventoy.net/
[Chaotic-AUR]: https://aur.chaotic.cx/
[ly]: https://github.com/fairyglade/ly
