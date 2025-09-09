#!/usr/bin/env bash
#set -euo pipefail
export LC_ALL=C LANG=C

#---------------------------------------
# Modern Raspbian/DietPi F2FS Flash Script
# With tmpfs acceleration and first-boot resize
# FZF file + device selectors used if -i/-d not provided
#---------------------------------------

usage() {
  cat <<EOF
Usage: $0 [-i image] [-d device] [-s] [-h]

Options:
  -i IMAGE      Source Raspberry Pi OS/DietPi image (.img or .img.xz) or URL
  -d DEVICE     Target block device (SD card, USB drive). If omitted you'll get an fzf selector.
  -s            Optional: enable SSH
  -h            Show this help
EOF
  exit 1
}

#---------------------------------------
# Root check
#---------------------------------------
sudo -v
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root."
  exec sudo -E bash "$0" "$@"
fi

#---------------------------------------
# Parse arguments
#---------------------------------------
IMAGE=""
DEVICE=""
ENABLE_SSH=0

while getopts "i:d:sh" opt; do
  case $opt in
    i) IMAGE="$OPTARG" ;;
    d) DEVICE="$OPTARG" ;;
    s) ENABLE_SSH=1 ;;
    h|*) usage ;;
  esac
done

#---------------------------------------
# fzf-backed file picker (start at $HOME)
# returns chosen path in IMAGE
#---------------------------------------
fzf_file_picker() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf required"; return 1; }

  # prefer fd
  if command -v fd >/dev/null 2>&1; then
    fd -H -t f -e img -e xz --hidden --follow . "$HOME" \
      | fzf --height=40% --layout=reverse --inline-info --prompt="Select image: " \
            --header="Select Raspberry Pi/DietPi image (.img, .img.xz, .xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --select-1 --exit-0 --no-multi
    return $?
  fi

  # fallback: find with nulls
  find "$HOME" -type f \( -iname '*.img' -o -iname '*.img.xz' -o -iname '*.xz' \) -print0 \
    | fzf --read0 --height=40% --layout=reverse --inline-info --prompt="Select image: " \
          --header="Select Raspberry Pi/DietPi image (.img, .img.xz, .xz)" \
          --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
          --preview-window=right:50%:wrap --select-1 --exit-0 --no-multi
  return $?
}

# If image not supplied, let user pick one via fzf
if [[ -z "$IMAGE" ]]; then
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf required to select an image interactively. Install fzf or pass -i IMAGE."; usage
  fi
  IMAGE="$(fzf_file_picker)"
  if [[ -z "$IMAGE" ]]; then
    echo "No image selected."; usage
  fi
fi

# If device not supplied use fzf selector
if [ -z "${DEVICE:-}" ]; then
  if ! command -v lsblk >/dev/null 2>&1; then
    echo "lsblk required but not found."
    exit 1
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf not found. Install fzf or pass -d /dev/sdX."
    exit 1
  fi

  # build selectable list: only disks, removable (RM==1), and not mounted
  # use lsblk -P for safe parsing when MODEL contains spaces
  SEL=$(
    lsblk -ASndPo NAME,TYPE,MODEL,MOUNTPOINT,RM -P \
      | awk -F '"' '$4=="disk" && $10==1 && $8=="" {printf "/dev/%s\t%s\n",$2,$6}' \
      | fzf --height=40% --style=minimal --inline-info +s --reverse \
            --prompt="Select target device: " --header="Path\tModel" \
            --select-1 --exit-0 --no-multi
  )

  if [ -z "${SEL:-}" ]; then
    echo "No device selected"
    exit 1
  fi

  # SEL format: "/dev/sdX<TAB>Model..."; extract path
  DEVICE=$(printf '%s' "$SEL" | awk '{print $1}')
fi

[ -b "$DEVICE" ] || { echo "Target device $DEVICE does not exist."; exit 1; }

#---------------------------------------
# Setup working directories
#---------------------------------------
WORKDIR=$(mktemp -d)
SRC_IMG="$WORKDIR/source.img"
BOOT_MNT="$WORKDIR/boot"
ROOT_MNT="$WORKDIR/root"
mkdir -p "$BOOT_MNT" "$ROOT_MNT"

#---------------------------------------
# Download or extract image
#---------------------------------------
echo "[*] Preparing source image..."
if printf '%s\n' "$IMAGE" | grep -qE '^https?://'; then
  echo "[*] Downloading $IMAGE ..."
  wget -q --show-progress -O "$WORKDIR/$(basename "$IMAGE")" "$IMAGE"
  IMAGE="$WORKDIR/$(basename "$IMAGE")"
fi

if printf '%s\n' "$IMAGE" | grep -qE '\.xz$'; then
  echo "[*] Extracting $IMAGE ..."
  xz -dc "$IMAGE" > "$SRC_IMG"
else
  cp "$IMAGE" "$SRC_IMG"
fi

#---------------------------------------
# Partition and format target device
#---------------------------------------
echo "[*] WARNING: All data on $DEVICE will be destroyed!"
read -rp "Type yes to continue: " CONFIRM
[[ $CONFIRM != yes ]] && { echo "Aborted"; exit 1; }


echo "[*] Wiping existing partitions..."
sudo wipefs -af "$DEVICE"
sudo parted -s "$DEVICE" mklabel msdos
sudo parted -s "$DEVICE" mkpart primary fat32 0% 512MB
sudo parted -s "$DEVICE" mkpart primary 512MB 100%
sudo partprobe "$DEVICE"

# partition name handling for mmcblk / nvme
case "$DEVICE" in
  *mmcblk*|*nvme*)
    PART_BOOT="${DEVICE}p1"
    PART_ROOT="${DEVICE}p2"
    ;;
  *)
    PART_BOOT="${DEVICE}1"
    PART_ROOT="${DEVICE}2"
    ;;
esac

echo "[*] Formatting partitions..."
sudo mkfs.vfat -F32 -n boot "$PART_BOOT"

# Hot/cold files for f2fs
HOT='db,sqlite,tmp,log,json,conf,journal,pid,lock,xml,ini,py'
TXT='pdf,txt,sh,ttf,otf,woff,woff2'
IMG='jpg,jpeg,png,webp,avif,jxl,gif,svg'
MED='mkv,mp4,mov,avi,webm,mpeg,mp3,ogg,opus,wav'
ZIP='img,iso,gz,tar,zip,deb'
COLD="${TXT},${IMG},${MED},${ZIP}"

sudo -E mkfs.f2fs -f -S -i \
  -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr \
  -E "$HOT" -e "$COLD" -l root "$PART_ROOT"

#---------------------------------------
# Mount source image partitions
#---------------------------------------
echo "[*] Mounting source image..."
LOOP_DEV=$(losetup --show -fP "$SRC_IMG")
mount "${LOOP_DEV}p1" "$BOOT_MNT"
mount "${LOOP_DEV}p2" "$ROOT_MNT"

#---------------------------------------
# Mount target partitions
#---------------------------------------
TARGET_BOOT="$WORKDIR/target_boot"
TARGET_ROOT="$WORKDIR/target_root"
mkdir -p "$TARGET_BOOT" "$TARGET_ROOT"
mount "$PART_BOOT" "$TARGET_BOOT"
mount "$PART_ROOT" "$TARGET_ROOT"

#---------------------------------------
# Tmpfs acceleration for root copy
#---------------------------------------
echo "[*] Copying root filesystem via tmpfs..."
ROOT_SIZE_MB=$(du -sm "$ROOT_MNT" | awk '{print $1}')
TMPFS_SIZE=$((ROOT_SIZE_MB + 512))  # add buffer
TMPFS_MNT="$WORKDIR/tmpfs_root"

mkdir -p "$TMPFS_MNT"
mount -t tmpfs -o size=${TMPFS_SIZE}M tmpfs "$TMPFS_MNT"

echo "[*] rsync from image to tmpfs..."
rsync -aHAX "$ROOT_MNT/" "$TMPFS_MNT/"

echo "[*] rsync from tmpfs to target root partition..."
rsync -aHAX --progress "$TMPFS_MNT/" "$TARGET_ROOT/"

umount "$TMPFS_MNT"
rm -rf "$TMPFS_MNT"

#---------------------------------------
# Copy boot partition
#---------------------------------------
echo "[*] Copying boot partition..."
rsync -aHAX "$BOOT_MNT/" "$TARGET_BOOT/"

#---------------------------------------
# Update bootloader and fstab for F2FS
#---------------------------------------
BOOT_UUID=$(blkid -s PARTUUID -o value "$PART_BOOT")
ROOT_UUID=$(blkid -s PARTUUID -o value "$PART_ROOT")

sed -i "s|root=[^ ]*|root=PARTUUID=$ROOT_UUID|" "$TARGET_BOOT/cmdline.txt"
sed -i "s|rootfstype=[^ ]*|rootfstype=f2fs|" "$TARGET_BOOT/cmdline.txt"

cat > "$TARGET_ROOT/etc/fstab" <<EOF
proc                  /proc   proc    defaults                    0   0
PARTUUID=$BOOT_UUID  /boot   vfat    defaults                    0   2
PARTUUID=$ROOT_UUID  /       f2fs    defaults,noatime,discard    0   1
EOF

#---------------------------------------
# Optional SSH setup
#---------------------------------------
if [ "$ENABLE_SSH" -eq 1 ]; then
  touch "$TARGET_ROOT/boot/ssh"
fi

#---------------------------------------
# First-boot F2FS resize script
#---------------------------------------
echo "[*] Creating first-boot F2FS resize script..."
mkdir -p "$TARGET_ROOT/etc/initramfs-tools/scripts/init-premount"
cat > "$TARGET_ROOT/etc/initramfs-tools/scripts/init-premount/f2fsresize" <<'EOF'
#!/bin/sh
# Initramfs script to expand F2FS root filesystem on first boot
. /scripts/functions

log_begin_msg "Expanding F2FS root filesystem..."
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [ -x /sbin/resize.f2fs ]; then
  /sbin/resize.f2fs "$ROOT_DEV"
  log_end_msg "F2FS root filesystem expanded."
  rm -f /etc/initramfs-tools/scripts/init-premount/f2fsresize
else
  log_end_msg "resize.f2fs not found. Skipping."
fi
EOF

chmod +x "$TARGET_ROOT/etc/initramfs-tools/scripts/init-premount/f2fsresize"

#---------------------------------------
# Cleanup
#---------------------------------------
echo "[*] Syncing and unmounting..."
sync
umount "$BOOT_MNT" "$ROOT_MNT" "$TARGET_BOOT" "$TARGET_ROOT"
losetup -d "$LOOP_DEV"
rm -rf "$WORKDIR"

echo "[+] Done! Your F2FS Raspberry Pi image is ready on $DEVICE."
echo "[+] First boot will automatically expand the root filesystem."
