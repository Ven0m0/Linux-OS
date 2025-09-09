#!/usr/bin/env bash
# Raspberry Pi Image to SD with F2FS Root
# Modernized merge of raspbian-f2fs and simpler kpartx script
# Supports Raspberry Pi 4 / DietPi / modern Raspberry Pi OS images

set -euo pipefail
export LC_ALL=C LANG=C

p() { printf '%s\n' "$*"; }

# --- Check for root ---
if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must be run as root."
    exec sudo bash "$0" "$@"
fi

# --- Arguments ---
IMAGE="$1"
CARD="$2"

if [[ -z "$IMAGE" || -z "$CARD" ]]; then
    p "Usage: $0 <raspberry_image.img> <sdcard>"
    exit 1
fi
if [[ ! -f "$IMAGE" ]]; then
    p "Error: image '$IMAGE' not found."
    exit 1
fi
if [[ ! -b "$CARD" ]]; then
    p "Error: target '$CARD' is not a block device."
    exit 1
fi

read -rp "WARNING: All data on $CARD will be erased. Continue? (y/N) " REPLY
[[ "$REPLY" =~ ^[Yy]$ ]] || exit 1

# --- Setup temp mount points ---
mkdir -p /tmp/sd /tmp/img

cleanup() {
    umount /tmp/sd 2>/dev/null || true
    umount /tmp/img 2>/dev/null || true
    kpartx -d "$IMAGE" 2>/dev/null || true
    rmdir /tmp/{sd,img} 2>/dev/null || true
}
trap cleanup EXIT SIGINT

# --- Unmount target ---
umount "${CARD}"* 2>/dev/null || true

# --- Create partitions ---
wipefs -af "$CARD"
parted -s "$CARD" mklabel msdos
parted -s "$CARD" mkpart primary fat32 0% 512MB
parted -s "$CARD" mkpart primary 512MB 100%
partprobe "$CARD"
sleep 1

# --- Determine partition suffix ---
if [[ "$CARD" =~ mmcblk ]]; then
    PARTBASE="${CARD}p"
else
    PARTBASE="$CARD"
fi

# --- Format partitions ---
mkfs.vfat -F32 "${PARTBASE}1" -n BOOT
mkfs.f2fs -f -O extra_attr,compression,noatime,discard "${PARTBASE}2" -l ROOT

# --- Mount partitions ---
mount "${PARTBASE}1" /tmp/sd

# --- Mount image partitions via kpartx ---
OUT=$(kpartx -av "$IMAGE")
LOOPDEV=$(echo "$OUT" | sed -n 's/^add map \(loop[^p]*\)p.*/\1/p' | head -1)
mount "/dev/mapper/${LOOPDEV}p1" /tmp/img

# --- Copy boot ---
p "Copying boot partition..."
rsync -aHAXx --info=progress2 /tmp/img/ /tmp/sd/

# --- Adjust cmdline.txt ---
PARTUUIDBOOT=$(blkid -s PARTUUID -o value "${PARTBASE}1")
PARTUUIDROOT=$(blkid -s PARTUUID -o value "${PARTBASE}2")
sed -i "s|root=[^ ]*|root=PARTUUID=${PARTUUIDROOT}|; s|rootfstype=[^ ]*|rootfstype=f2fs|; s|init=[^ ]*||" /tmp/sd/cmdline.txt

umount /tmp/sd
umount /tmp/img

# --- Mount root partitions ---
mount "${PARTBASE}2" /tmp/sd
mount "/dev/mapper/${LOOPDEV}p2" /tmp/img

# --- Copy root ---
p "Copying root partition (can take a few minutes)..."
rsync -aHAXx --info=progress2 /tmp/img/ /tmp/sd/

# --- Adjust fstab ---
sed -i "s|/boot.*vfat|/boot vfat defaults 0 2|; s|/ .*ext4|/ f2fs defaults,noatime,discard 0 1|" /tmp/sd/etc/fstab

umount /tmp/sd
umount /tmp/img
kpartx -d "$IMAGE"

# --- Optional: SSH enable ---
read -rp "Enable SSH by default? (y/N) " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    mount "${PARTBASE}1" /tmp/sd
    touch /tmp/sd/ssh
    umount /tmp/sd
fi

p "All done! You can now insert the SD card into your Raspberry Pi and boot it."
trap - EXIT
