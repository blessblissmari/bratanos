#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# archiso profile definition for BratanOS.
# Roughly modeled after the upstream `releng` profile.

iso_name="bratanos"
iso_label="BRATANOS_$(date +%Y%m)"
iso_publisher="BratanOS <https://github.com/blessblissmari/bratanos>"
iso_application="BratanOS Live/Install Medium"
iso_version="$(date +%Y.%m.%d)"
install_dir="bratanos"
buildmodes=('iso')
bootmodes=(
    'bios.syslinux.mbr'
    'bios.syslinux.eltorito'
    'uefi-ia32.grub.esp'
    'uefi-x64.grub.esp'
    'uefi-ia32.grub.eltorito'
    'uefi-x64.grub.eltorito'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# Permissions for files placed by airootfs/ (octal).
declare -A file_permissions=(
  ["/etc/shadow"]="0:0:0400"
  ["/etc/gshadow"]="0:0:0400"
  ["/etc/sudoers.d/bratanos"]="0:0:0440"
  ["/root"]="0:0:0750"
  ["/root/.automated_script.sh"]="0:0:0755"
  ["/usr/bin/bratan-tidy"]="0:0:0755"
  ["/usr/local/bin/pacman"]="0:0:0755"
  ["/usr/bin/bratanos-grub-install"]="0:0:0755"
  ["/etc/bratanos/chaotic-aur-setup.sh"]="0:0:0755"
  ["/etc/profile.d/00-bratanos-pacman-path.sh"]="0:0:0755"
)
