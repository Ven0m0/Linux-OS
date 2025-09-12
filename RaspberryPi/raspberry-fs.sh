#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

HOMEDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -P -- "$HOMEDIR" || exit 1

# quick helpers
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { printf '%s required\n' "$1"; exit 1; }
}

# minimal preflight (core commands)
for cmd in losetup parted mkfs.f2fs mkfs.vfat rsync tar xz curl blkid; do
  require_cmd "$cmd"
done

usage() {
  cat <<EOF
Usage: $0 [-i image_or_url] [-d /dev/sdX] [-s] [-h]
  -i IMAGE or URL   source .img or .img.xz (or http(s) URL)
  -d DEVICE         target block device (if omitted you'll get an fzf selector)
  -s                enable SSH on first boot
  -h                help
EOF
  exit 1
}

cleanup() {
  umount "${BOOT_MNT:-}" "${ROOT_MNT:-}" "${TARGET_BOOT:-}" "${TARGET_ROOT:-}" 2>/dev/null || :
  [ -n "${TMPFS_MNT:-}" ] && umount "${TMPFS_MNT:-}" 2>/dev/null || :
  [ -n "${LOOP_DEV:-}" ] && losetup -d "$LOOP_DEV" 2>/dev/null || :
  [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

# root check
if [ "$(id -u)" != 0 ]; then
  echo "must run as root; re-exec with sudo..."
  exec sudo -E bash "$0" "$@"
fi

# args
IMAGE=""
DEVICE=""
ENABLE_SSH=0

while getopts "i:d:sh" opt; do
  case "$opt" in
    i) IMAGE="$OPTARG" ;;
    d) DEVICE="$OPTARG" ;;
    s) ENABLE_SSH=1 ;;
    h|*) usage ;;
  esac
done

# optional fd/fzf helpers will be checked when used
fzf_file_picker() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf required for interactive selection"; usage; }
  if command -v fd >/dev/null 2>&1; then
    # fd -p is alias for --full-path on newer fd versions
    fd -tf -e img -e xz -p "${HOME:-.}" \
      | fzf --height=~40% --layout=reverse --inline-info --prompt="Select image: " \
            --header="Select image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
  else
    find "${HOME:-.}" -type f \( -iname '*.img' -o -iname '*.xz' \) -print0 \
      | fzf --read0 --height=~40% --layout=reverse --inline-info --prompt="Select image: " \
            --header="Select image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
  fi
}

# choose image if not provided
if [ -z "${IMAGE:-}" ]; then
  IMAGE="$(fzf_file_picker)"
  [ -z "$IMAGE" ] && { echo "no image selected"; usage; }
fi

# device selector (only check fzf when needed)
if [ -z "${DEVICE:-}" ]; then
  command -v fzf >/dev/null 2>&1 || { echo "fzf required for device selection"; usage; }
  SEL=$(
    lsblk -dn -o NAME,TYPE,RM,SIZE,MODEL,MOUNTPOINT \
      | awk '$2=="disk" && $3=="1" && ($6=="" || $6=="-") { printf "/dev/%s\t%s %s\n",$1,$4,$5 }' \
      | fzf --height=~40% --layout=reverse --inline-info --prompt="Select target device: " \
            --header="Path\tSize Model" --no-multi -1 -0
  )
  [ -z "${SEL:-}" ] && { echo "no device selected"; exit 1; }
  DEVICE=$(awk '{print $1}' <<<"$SEL")
fi

[ ! -b "$DEVICE" ] && { echo "target device $DEVICE not found or not a block device"; exit 1; }

# working dirs
WORKDIR="$(mktemp -d)"
SRC_IMG="${WORKDIR}/source.img"
BOOT_MNT="${WORKDIR}/boot"
ROOT_MNT="${WORKDIR}/root"
mkdir -p -- "$BOOT_MNT" "$ROOT_MNT"

# ---- CURL fix: preserve URL, write to local file ----
case "$IMAGE" in
  http://*|https://*)
    SRC_URL="$IMAGE"
    IMAGE="${WORKDIR}/$(basename "$SRC_URL")"
    curl -SfL --progress-bar -o "$IMAGE" "$SRC_URL"
    ;;
  *) ;;
esac

# extract or copy
case "$IMAGE" in
  *.xz) xz -dc "$IMAGE" > "$SRC_IMG" ;;
  *) cp --reflink=auto "$IMAGE" "$SRC_IMG" ;;
esac

# partition & format
echo "[*] WARNING: all data on ${DEVICE} will be destroyed!"
read -r -p "Type yes to continue: " CONFIRM
[ "$CONFIRM" != yes ] && { echo "aborted"; exit 1; }

wipefs -af "$DEVICE"
parted -s "$DEVICE" mklabel msdos
parted -s "$DEVICE" mkpart primary fat32 0% 512MB
parted -s "$DEVICE" mkpart primary 512MB 100%
partprobe "$DEVICE"
# ensure udev created device nodes
udevadm settle || true

case "$DEVICE" in
  *mmcblk*|*nvme*) PART_BOOT="${DEVICE}p1"; PART_ROOT="${DEVICE}p2" ;;
  *) PART_BOOT="${DEVICE}1"; PART_ROOT="${DEVICE}2" ;;
esac

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

# mount source image partitions
LOOP_DEV="$(losetup --show -fP "$SRC_IMG")"
mount "${LOOP_DEV}p1" "$BOOT_MNT"
mount "${LOOP_DEV}p2" "$ROOT_MNT"

# mount target partitions
TARGET_BOOT="${WORKDIR}/target_boot"
TARGET_ROOT="${WORKDIR}/target_root"
mkdir -p "$TARGET_BOOT" "$TARGET_ROOT"
mount "$PART_BOOT" "$TARGET_BOOT"
mount "$PART_ROOT" "$TARGET_ROOT"

# helper: get best tmpfs free (MB)
get_free_tmpfs_mb() {
  best=0
  for m in /dev/shm /run/shm /tmp; do
    [ -e "$m" ] || continue
    val="$( (df -Pm "$m" 2>/dev/null | awk 'NR==2{print $4}') || printf '0' )"
    case "$val" in ''|*[!0-9]*) val=0 ;; esac
    if [ "$val" -gt "$best" ]; then best=$val; fi
  done
  printf '%s' "$best"
}

# copy root: tar-stream with optional tmpfs, fallback rsync
ROOT_SIZE_MB="$(du -sm "$ROOT_MNT" | awk '{print $1}')"
TMPFS_SIZE=$((ROOT_SIZE_MB + 512))
TMPFS_MNT="${WORKDIR}/tmpfs_root"
FREE_MB="$(get_free_tmpfs_mb)"

echo "[*] Copying root filesystem..."
if [ "$FREE_MB" -ge "$TMPFS_SIZE" ]; then
  mkdir -p "$TMPFS_MNT"
  mount -t tmpfs -o size="${TMPFS_SIZE}"M tmpfs "$TMPFS_MNT"
  (cd "$ROOT_MNT" && tar -cpf - .) | (cd "$TMPFS_MNT" && tar -xpf -)
  (cd "$TMPFS_MNT" && tar -cpf - .) | (cd "$TARGET_ROOT" && tar -xpf -)
  umount "$TMPFS_MNT"
  rm -rf "$TMPFS_MNT"
else
  echo "[!] not enough tmpfs; falling back to rsync"
  rsync -aHAX --inplace --fsync --no-whole-file --progress "${ROOT_MNT}/" "${TARGET_ROOT}/"
fi

# copy boot (tar-stream if small mem)
echo "[*] Copying boot partition..."
if [ "$FREE_MB" -ge 128 ]; then
  (cd "$BOOT_MNT" && tar -cpf - .) | (cd "$TARGET_BOOT" && tar -xpf -)
else
  rsync -aHAX --inplace --fsync --no-whole-file --progress "${BOOT_MNT}/" "${TARGET_BOOT}/"
fi

# update bootloader & fstab
BOOT_UUID="$(blkid -s PARTUUID -o value "$PART_BOOT" 2>/dev/null || true)"
ROOT_UUID="$(blkid -s PARTUUID -o value "$PART_ROOT" 2>/dev/null || true)"

if [ -f "${TARGET_BOOT}/cmdline.txt" ]; then
  sed -i "s|root=[^ ]*|root=PARTUUID=$ROOT_UUID|" "${TARGET_BOOT}/cmdline.txt" || true
  sed -i "s|rootfstype=[^ ]*|rootfstype=f2fs|" "${TARGET_BOOT}/cmdline.txt" || true
fi

mkdir -p "${TARGET_ROOT}/etc"
cat > "${TARGET_ROOT}/etc/fstab" <<EOF
proc                  /proc   proc    defaults                    0   0
PARTUUID=$BOOT_UUID  /boot   vfat    defaults                    0   2
PARTUUID=$ROOT_UUID  /       f2fs    defaults,noatime,discard    0   1
EOF

# optional ssh
if [ "$ENABLE_SSH" -eq 1 ]; then
  touch "${TARGET_BOOT}/ssh"
fi

# first-boot f2fs resize script
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

# final sync + cleanup handled by trap
sync
umount "$BOOT_MNT" "$ROOT_MNT" "$TARGET_BOOT" "$TARGET_ROOT" 2>/dev/null || :
losetup -d "${LOOP_DEV:-}" 2>/dev/null || :
rm -rf "${WORKDIR:-}"

echo "[+] Done. F2FS Raspberry Pi image ready on ${DEVICE}."
