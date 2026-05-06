# Contributing to BratanOS

Thanks for stopping by. BratanOS is intentionally tiny so anyone can
hold the whole thing in their head — please keep it that way.

## Ground rules

- **Simplicity over cleverness.** If you can't explain a script in
  three sentences, it's too clever. Bash + pacman + systemd. No DSLs,
  no new package managers, no immutable FS.
- **No bundled binaries in `git`.** Anything binary (icons, wallpapers)
  must be small and unambiguously yours, or generated at build time.
- **Test what you write.** `make lint` for shell, `cargo check` for the
  flasher, `make iso-docker` to confirm the ISO still builds.

## Layout

See [README.md](./README.md#repo-layout). Most contributions land in
one of:

- `src/bratan-tidy/` — the cleanup logic
- `src/bratan-pacman/` — the AUR-fallback wrapper
- `archiso/` — packages, defaults, branding
- `installer/` — the Tauri flasher
- `web/` — landing page

## Code style

- **Bash**: `set -uo pipefail` at the top, ShellCheck-clean. Prefer
  small functions over giant `case` blocks.
- **Rust**: rustfmt-clean. Prefer trait-based platform splits (see
  `installer/src-tauri/src/disk.rs`) over `cfg!` ladders inside one
  function.
- **JS**: no frameworks. Vanilla DOM, ES modules.

## Pull requests

- Open against `main`.
- Include a 2–3 sentence description of *why*, not just *what*.
- If you change `bratan-tidy`'s defaults, update `tidy.conf` and the
  README table.
- If you add a system service, wire it into the right
  `*.target.wants/` symlink under `archiso/airootfs/etc/systemd/system/`.

## Filing issues

Tell us:
- BratanOS version (`cat /etc/os-release` → `BUILD_ID`)
- Output of `bratan-tidy --status`
- The shortest `pacman` command that reproduces the issue.
