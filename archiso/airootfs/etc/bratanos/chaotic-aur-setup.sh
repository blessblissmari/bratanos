#!/usr/bin/env bash
# Enable Chaotic-AUR — a binary repo of prebuilt AUR packages — so
# `sudo pacman -S brave-bin` etc. just works without compiling.
#
# Idempotent. Safe to re-run.
#
# Reference: https://aur.chaotic.cx/

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "must be root" >&2
    exit 1
fi

KEY_ID="3056513887B78AEB"
KEYRING_URL="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst"
MIRRORLIST_URL="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"

echo "[bratanos] receiving Chaotic-AUR signing key…"
pacman-key --recv-key "$KEY_ID" --keyserver keyserver.ubuntu.com
pacman-key --lsign-key "$KEY_ID"

echo "[bratanos] installing chaotic-keyring + chaotic-mirrorlist…"
pacman -U --noconfirm "$KEYRING_URL" "$MIRRORLIST_URL"

if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
    echo "[bratanos] appending [chaotic-aur] to /etc/pacman.conf"
    cat >>/etc/pacman.conf <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
fi

echo "[bratanos] syncing databases…"
pacman -Sy

echo "[bratanos] Chaotic-AUR enabled. Try:  sudo pacman -S brave-bin"
