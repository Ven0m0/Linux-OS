#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C
WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd -- "$WORKDIR"
# Colors
RED=$'\e[31m' GRN=$'\e[32m' DEF=$'\e[0m'
#p() { printf '%s\n' "$*" 2>/dev/null; }
pe() { printf '%b\n' "$*"$'\e[0m' 2>/dev/null; }
# Check dependencies:
if ! command -v kpartx &>/dev/null; then
  pe "${RED}Installing missing dependency: kpartx"
  sudo pacman -S multipath-tools --needed --noconfirm -q >/dev/null
fi
# Auto-select ISO
iso="${1:-$(find . -maxdepth 1 -type f \( -iname '*raspberry*.img' -o -iname '*dietpi*.img' \) | head -n1)}"
iso="${iso##*/}"
# Auto-select USB
usb="${2:-$(lsblk -rniA -o NAME,TYPE | awk '$2=="part"{print $1}' | grep -E '^sd[a-z][0-9]+$' | sort -V | tail -n1)}"
# Check ISO exists
if [[ ! -f $iso ]]; then
    pe "${RED}File not found: $iso"
    exit 1
fi
# Confirm with user
pe "${GRN}Found file: $iso"
read -rp "Flash $iso to $usb? [y/N] " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    pe "${RED}Aborted"
    exit 1
fi
# Make flashing script executable and call it
chmod u+x "$WORKDIR/raspberry_f2fs.sh"
sudo -v
sudo "$WORKDIR/raspberry_f2fs.sh" "$iso" "$usb"
