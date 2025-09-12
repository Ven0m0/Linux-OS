#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

HOMEDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -P -- "$HOMEDIR" || exit 1

#---------------------------------------
# Modern Raspbian/DietPi F2FS Flash Script
# With tmpfs acceleration, tar-stream copy, and first-boot resize
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
  umount "${BOOT_MNT:-}" "${ROOT_MNT:-}" "${TARGET_BOOT:-}" "${TARGET_ROOT:-}" 2>/dev/null || :
  [ "${LOOP_DEV:-}" != "" ] && losetup -d "$LOOP_DEV" 2>/dev/null || :
  [ "${WORKDIR:-}" != "" ] && rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

#---------------------------------------
# Root check
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
# fzf-backed file picker
#---------------------------------------
fzf_file_picker(){
  command -v fzf >/dev/null 2>&1 || { echo "fzf required"; usage; }
  if command -v fd >/dev/null 2>&1; then
    LC_ALL=C fd -tf -e img -e xz -p "${HOME:-.}" \
      | fzf --height=~40% --layout=reverse --inline-info --prompt="Select image: " \
            --header="Select Raspberry Pi/DietPi image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
  else
    LC_ALL=C find "${HOME:-.}" -type f \( -iname '*.img' -o -iname '*.xz' \) -print0 \
      | fzf --read0 --height=~40% --layout=reverse --inline-info --prompt="Select image: " \
            --header="Select Raspberry Pi/DietPi image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
  fi
}
# If image not supplied, let user pick one
if [ "${IMAGE:-}" = "" ]; then
  IMAGE="$(fzf_file_picker)"
  [[ -z "$IMAGE" ]] && { echo "No image selected."; usage; }
fi

#---------------------------------------
# fzf-backed device picker
#---------------------------------------
if [ "${DEVICE:-}" = "" ]; then
  command -v fzf >/dev/null 2>&1 || { echo "fzf required"; usage; }
  SEL=$(
    lsblk -dn -o NAME,TYPE,RM,SIZE,MODEL,MOUNTPOINT \
      | awk '$2=="disk" && $3=="1" && $6=="" { printf "/dev/%s\t%s %s\n",$1,$4,$5 }' \
      | fzf --height=~40% --layout=reverse --inline-info --prompt="Select target device: " \
            --header="Path\tSize Model" --no-multi -1 -0
  )
  [[ -z "$SEL" ]] && { echo "No device selected"; exit 1; }
  DEVICE=$(awk '{print $1}' <<<"$SEL")
fi

[[ ! -b "$DEVICE" ]] && { echo "Target device $DEVICE does not exist or is not a block device."; exit 1; }

#---------------------------------------
# Setup working directories
#---------------------------------------
WORKDIR=$(mktemp -d)
SRC_IMG="${WORKDIR}/source.img"
BOOT_MNT="${WORKDIR}/boot"
ROOT_MNT="${WORKDIR}/root"
mkdir -p "$BOOT_MNT" "$ROOT_MNT"

#---------------------------------------
# Download or extract image
#---------------------------------------
echo "[*] Preparing source image..."
if [[ "$IMAGE" =~ ^https?:// ]]; then
  echo "[*] Downloading $IMAGE ..."
  IMAGE="${WORKDIR}/$(basename "$IMAGE")"
  curl -SfL --progress-bar -o "$IMAGE" "$IMAGE"
fi
if [[ "$IMAGE" =~ \.xz$ ]]; then
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
[ "$CONFIRM" != yes ] && { echo "Aborted"; exit 1; }

echo "[*] Wiping existing partitions..."
wipefs -af "$DEVICE"
parted -s "$DEVICE" mklabel msdos
parted -s "$DEVICE" mkpart primary fat32 0% 512MB
parted -s "$DEVICE" mkpart primary 512MB 100%
partprobe "$DEVICE"

case "$DEVICE" in
  *mmcblk*|*nvme*) PART_BOOT="${DEVICE}p1"; PART_ROOT="${DEVICE}p2" ;;
  *) PART_BOOT="${DEVICE}1"; PART_ROOT="${DEVICE}2" ;;
esac

echo "[*] Formatting partitions..."
mkfs.vfat -F32 -n boot "$PART_BOOT"

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
# Mount partitions
#---------------------------------------
echo "[*] Mounting source and target partitions..."
LOOP_DEV=$(losetup --show -fP "$SRC_IMG")
mount "${LOOP_DEV}p1" "$BOOT_MNT"
mount "${LOOP_DEV}p2" "$ROOT_MNT"

TARGET_BOOT="${WORKDIR}/target_boot"
TARGET_ROOT="${WORKDIR}/target_root"
mkdir -p "$TARGET_BOOT" "$TARGET_ROOT"
mount "$PART_BOOT" "$TARGET_BOOT"
mount "$PART_ROOT" "$TARGET_ROOT"

#---------------------------------------
# Copy root filesystem
#---------------------------------------
echo "[*] Copying root filesystem..."
ROOT_SIZE_MB=$(du -sm "$ROOT_MNT" | awk '{print $1}')
TMPFS_SIZE=$((ROOT_SIZE_MB + 512))
TMPFS_MNT="${WORKDIR}/tmpfs_root"
FREE_MB=$(df -Pm /dev/shm | awk 'NR==2 {print $4}')

if [ "$FREE_MB" -ge "$TMPFS_SIZE" ]; then
  echo "[*] Using tmpfs (${TMPFS_SIZE}M needed, ${FREE_MB}M available)..."
  mkdir -p "$TMPFS_MNT"
  mount -t tmpfs -o size="${TMPFS_SIZE}"M tmpfs "$TMPFS_MNT"

  (cd "$ROOT_MNT" && tar -cpf - .) | (cd "$TMPFS_MNT" && tar -xpf -)
  (cd "$TMPFS_MNT" && tar -cpf - .) | (cd "$TARGET_ROOT" && tar -xpf -)

  umount "$TMPFS_MNT"
  rm -rf "$TMPFS_MNT"
else
  echo "[!] Not enough memory for tmpfs, falling back to rsync..."
  rsync -aHAX --inplace --fsync --no-whole-file --progress \
        "${ROOT_MNT}/" "${TARGET_ROOT}/"
fi

#---------------------------------------
# Copy boot partition
#---------------------------------------
echo "[*] Copying boot partition..."
if [ "$FREE_MB" -ge 128 ]; then
  (cd "$BOOT_MNT" && tar -cpf - .) | (cd "$TARGET_BOOT" && tar -xpf -)
else
  rsync -aHAX --inplace --fsync --no-whole-file --progress \
        "${BOOT_MNT}/" "${TARGET_BOOT}/"
fi

#---------------------------------------
# Update bootloader and fstab
#---------------------------------------
BOOT_UUID=$(blkid -s PARTUUID -o value "$PART_BOOT" || :)
ROOT_UUID=$(blkid -s PARTUUID -o value "$PART_ROOT" || :)

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
[ "$ENABLE_SSH" -eq 1 ] && touch "${TARGET_BOOT}/ssh"

#---------------------------------------
# First-boot F2FS resize script
#---------------------------------------
echo "[*] Creating first-boot F2FS resize script..."
mkdir -p "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount"
cat > "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount/f2fsresize" <<'EOF'
#!/bin/sh
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
# Cleanup
#---------------------------------------
echo "[*] Syncing and unmounting..."
sync
umount "$BOOT_MNT" "$ROOT_MNT" "$TARGET_BOOT" "$TARGET_ROOT" 2>/dev/null || :
losetup -d "${LOOP_DEV:-}" 2>/dev/null || :
rm -rf "${WORKDIR:-}"

echo "[+] Done! Your F2FS Raspberry Pi image is ready on ${DEVICE}."
echo "[+] First boot will automatically expand the root filesystem."
