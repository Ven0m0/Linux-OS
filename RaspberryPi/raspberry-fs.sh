#!/usr/bin/env bash
WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd -- "$WORKDIR"
# Default ISO: first matching DietPi image if $1 not provided
find . -maxdepth 1 -type f \( -iname '*raspberry*.img' -o -iname '*dietpi*.img' \)
ISO="${1:-$(find raspberryos.img/DietPi_RPi*.img 2>/dev/null | head -n1)}"

# Default USB: first sdX device if $2 not provided
USB="${2:-$(lsblk -dniA -o NAME | grep -E '^sd[a-z]' | head -n1 | sed 's|^|/dev/|')}}"

if [[ -f $ISO ]]; then
    echo "Found file: $ISO"
    echo chmod +x "$WORKDIR/raspberry_f2fs.sh"
    sudo "$WORKDIR/raspberry_f2fs.sh" "$ISO" "$USB"
else
    echo "File not found!"; exit
fi

