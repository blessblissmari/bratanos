#!/usr/bin/env bash
# Live ISO welcome banner. Plays once on root's first tty1 login.
script_cmd="${1}"
if [[ -n "${script_cmd}" ]]; then
    exec "${script_cmd}"
fi

clear
cat <<'BANNER'
   ____               _              ___  ____
  | __ ) _ __ __ _  _| |_ __ _ _ __ / _ \/ ___|
  |  _ \| '__/ _` |/ _` |/ _` | '_ \ | | \___ \
  | |_) | | | (_| | || | | (_| | | | | |_| |__) |
  |____/|_|  \__,_|\__|_|\__,_|_| |_|\___/____/

  Live ISO — Arch + i3, no trash.

  • Install:   archinstall
  • Wi-Fi:     iwctl
  • Wired:     dhcpcd <iface>
  • Tidy:      bratan-tidy --status
BANNER
