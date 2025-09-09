#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

HOMEDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -- "$HOMEDIR" || exit 1

#---------------------------------------
# Modern Raspbian/DietPi F2FS Flash Script
# With tmpfs acceleration and first-boot resize
# FZF file + device selectors used if -i/-d not provided
#---------------------------------------
sudo -v; sync
sudo sh -c 'echo 3 >/proc/sys/vm/drop_caches' || :

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

cleanup() {
  # try to unmount if mounted, ignore errors
  [ -n "${BOOT_MNT:-}" ] && umount "$BOOT_MNT" 2>/dev/null || :
  [ -n "${ROOT_MNT:-}" ] && umount "$ROOT_MNT" 2>/dev/null || :
  [ -n "${TARGET_BOOT:-}" ] && umount "$TARGET_BOOT" 2>/dev/null || :
  [ -n "${TARGET_ROOT:-}" ] && umount "$TARGET_ROOT" 2>/dev/null || :
  if [ -n "${LOOP_DEV:-}" ]; then
    losetup -d "$LOOP_DEV" 2>/dev/null || :
  fi
  [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

#---------------------------------------
# Root check (re-exec under sudo if needed)
#---------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Re-exec with sudo..."
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
# returns chosen path in IMAGE (printed)
#---------------------------------------
fzf_file_picker(){
  command -v fzf >/dev/null 2>&1 || { echo "fzf required"; usage; }
  if command -v fd >/dev/null 2>&1; then
    LC_ALL=C fd -tf -e img -e xz -p "${HOME:-.}" \
      | fzf --height=~40% --layout=reverse --inline-info --prompt="Select image: " \
            --header="Select Raspberry Pi/DietPi image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
    return $?
  fi
  LC_ALL=C find -O3 "${HOME:-.}" -type f \( -iname '*.img' -o -iname '*.xz' \) -print0 \
    | fzf --read0 --height=~40% --layout=reverse --inline-info --prompt="Select image: " \
          --header="Select Raspberry Pi/DietPi image (.img,.xz)" \
          --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
          --preview-window=right:50%:wrap --no-multi -1 -0
  return $?
}
# If image not supplied, let user pick one via fzf
if [ -z "${IMAGE:-}" ]; then
  IMAGE="$(fzf_file_picker)"
  [[ -z "$IMAGE" ]] && { echo "No image selected."; usage; }
fi
# If device not supplied use fzf selector
if [ -z "${DEVICE:-}" ]; then
  command -v fzf &>/dev/null && { echo "fzf not found. Install fzf or pass -d /dev/sdX." exit 1; }
  SEL=$(
    lsblk -PAn -o NAME,TYPE,MODEL,MOUNTPOINT,RM \
      | while read -r line; do
          # turn NAME="sda" TYPE="disk" ... into shell vars
          eval "$line"
          if [[ "$TYPE" = disk ]] && [ "${RM:-0}" = "1" ] && [ -z "${MOUNTPOINT:-}" ]; then
            printf "/dev/%s\t%s\n" "$NAME" "${MODEL:-}"
          fi
        done \
      | fzf --height=~40% --style=minimal --inline-info +s --reverse -1 -0 \
            --prompt="Select target device: " --header="Path\tModel" --no-multi)
  
  [[ -z "${SEL:-}" ]] && { echo "No device selected"; exit 1; }
  DEVICE=$(printf '%s' "$SEL" | awk '{print $1}')
fi

[[ ! -b "$DEVICE" ]] && { echo "Target device $DEVICE does not exist or is not a block device."; exit 1; }

#---------------------------------------
# Setup working directories
#---------------------------------------
WORKDIR=$(mktemp -d)
SRC_IMG="${WORKDIR}/source.img"
BOOT_MNT="${WORKDIR}/boot"
ROOT_MNT="${WORKDIR}/root"
mkdir -p -- "$BOOT_MNT" "$ROOT_MNT"

#---------------------------------------
# Download or extract image
#---------------------------------------
echo "[*] Preparing source image..."
if printf '%s\n' "$IMAGE" | grep -qE '^https?://'; then
  echo "[*] Downloading $IMAGE ..."
  IMAGE="${WORKDIR}/$(basename "$IMAGE")"
  curl -SfL --progress-bar -o "$IMAGE" "$IMAGE"
fi
if printf '%s\n' "$IMAGE" | grep -qE '\.xz$'; then
  echo "[*] Extracting $IMAGE ..."
  xz -dc "$IMAGE" > "$SRC_IMG"
else
  cp --reflink=auto "$IMAGE" "$SRC_IMG"
fi

#---------------------------------------
# Partition and format target device
#---------------------------------------
echo "[*] WARNING: All data on ${DEVICE} will be destroyed!"
read -r -p "Type yes to continue: " CONFIRM
if [ "$CONFIRM" != yes ]; then
  echo "Aborted"; exit 1
fi

echo "[*] Wiping existing partitions..."
wipefs -af "$DEVICE"
parted -s "$DEVICE" mklabel msdos
parted -s "$DEVICE" mkpart primary fat32 0% 512MB
parted -s "$DEVICE" mkpart primary 512MB 100%
partprobe "$DEVICE"

# partition name handling for mmcblk / nvme -> needs sda + sdb handling
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
mkfs.vfat -F32 -n boot "$PART_BOOT"

# Hot/cold files for f2fs
HOT='db,sqlite,tmp,log,json,conf,journal,pid,lock,xml,ini,py'
TXT='pdf,txt,sh,ttf,otf,woff,woff2'
IMG='jpg,jpeg,png,webp,avif,jxl,gif,svg'
MED='mkv,mp4,mov,avi,webm,mpeg,mp3,ogg,opus,wav'
ZIP='img,iso,gz,tar,zip,deb'
COLD="${TXT},${IMG},${MED},${ZIP}"

mkfs.f2fs -f -S -i \
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
TARGET_BOOT="${WORKDIR}/target_boot"
TARGET_ROOT="${WORKDIR}/target_root"
mkdir -p "$TARGET_BOOT" "$TARGET_ROOT"
mount "$PART_BOOT" "$TARGET_BOOT"
mount "$PART_ROOT" "$TARGET_ROOT"

#---------------------------------------
# Tmpfs acceleration for root copy
#---------------------------------------
echo "[*] Copying root filesystem via tmpfs..."
ROOT_SIZE_MB=$(du -sm "${ROOT_MNT}" | awk '{print $1}')
TMPFS_SIZE=$((ROOT_SIZE_MB + 512))  # add buffer
TMPFS_MNT="${WORKDIR}/tmpfs_root"

mkdir -p "$TMPFS_MNT"
mount -t tmpfs -o size=${TMPFS_SIZE}M tmpfs "$TMPFS_MNT"

echo "[*] rsync from image to tmpfs..."
rsync -aHAX --progress --fsync --preallocate --force "${ROOT_MNT}/" "${TMPFS_MNT}/"

echo "[*] rsync from tmpfs to target root partition..."
rsync -aHAX --progress --fsync --preallocate --force "${TMPFS_MNT}/" "${TARGET_ROOT}/"

umount "$TMPFS_MNT"
rm -rf "$TMPFS_MNT"

#---------------------------------------
# Copy boot partition
#---------------------------------------
echo "[*] Copying boot partition..."
rsync -aHAX --progress --fsync --preallocate --force "${BOOT_MNT}/" "${TARGET_BOOT}/"

#---------------------------------------
# Update bootloader and fstab for F2FS
#---------------------------------------
BOOT_UUID=$(blkid -s PARTUUID -o value "$PART_BOOT" || :)
ROOT_UUID=$(blkid -s PARTUUID -o value "$PART_ROOT" || :)

# cmdline.txt lives on the boot partition for Raspberry Pi images
if [ -f "${TARGET_BOOT}/cmdline.txt" ]; then
  sed -i "s|root=[^ ]*|root=PARTUUID=$ROOT_UUID|" "${TARGET_BOOT}/cmdline.txt"
  sed -i "s|rootfstype=[^ ]*|rootfstype=f2fs|" "${TARGET_BOOT}/cmdline.txt" || :
fi

mkdir -p "${TARGET_ROOT}/etc"
cat > "${TARGET_ROOT}/etc/fstab" <<EOF
proc                  /proc   proc    defaults                    0   0
PARTUUID=$BOOT_UUID  /boot   vfat    defaults                    0   2
PARTUUID=$ROOT_UUID  /       f2fs    defaults,noatime,discard    0   1
EOF

#---------------------------------------
# Optional SSH setup
#---------------------------------------
if [ "$ENABLE_SSH" -eq 1 ]; then
  touch "${TARGET_BOOT}/ssh"
fi

#---------------------------------------
# First-boot F2FS resize script
#---------------------------------------
echo "[*] Creating first-boot F2FS resize script..."
mkdir -p "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount"
cat > "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount/f2fsresize" <<'EOF'
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

chmod +x "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount/f2fsresize" || :

#---------------------------------------
# Cleanup (trap will also run cleanup)
#---------------------------------------
echo "[*] Syncing and unmounting..."
sync
umount "$BOOT_MNT" "$ROOT_MNT" "$TARGET_BOOT" "$TARGET_ROOT" 2>/dev/null || :
losetup -d "${LOOP_DEV:-}" 2>/dev/null || :
rm -rf "${WORKDIR:-}"

echo "[+] Done! Your F2FS Raspberry Pi image is ready on ${DEVICE}."
echo "[+] First boot will automatically expand the root filesystem."
