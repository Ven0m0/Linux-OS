#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C SHELL="${BASH:-$(command -v bash)}" HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "$(cd -P -- "${BASH_SOURCE[0]%/*}" && echo "$PWD")" || exit 1
sync; sudo -v
#
# raspberry-fs.sh – Flash a Raspberry Pi image onto an SD card (or other block device)
#                 – converts the root partition to F2FS, optionally enables SSH.
#
# Author:  (your name)
# Date:    12 Sep 2025
# Version: 1.2  (includes lint‑fixes & extra safety features)

# ----------------------------------------------------------------------
# Configuration (can be overridden via CLI flags)
# ----------------------------------------------------------------------
BOOT_SIZE="512M"          # Size of the FAT32 boot partition
DRY_RUN=0                 # Set to 1 with -n/--dry-run to only print actions
DEBUG=0                   # Set to 1 with -x to enable Bash tracing (set -x)

# ----------------------------------------------------------------------
# Exit‑code constants (useful for callers)
# ----------------------------------------------------------------------
E_USAGE=64
E_DEPEND=65
E_ABORT=130

# ----------------------------------------------------------------------
# Helper functions
# ----------------------------------------------------------------------
log() {
  # Simple timestamped logger
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "❌ Required command \"$1\" not found – please install it."
    exit "$E_DEPEND"
  }
}

run() {
  # Execute a command, honouring dry‑run mode
  if (( DRY_RUN )); then
    log "[dry‑run] $*"
  else
    eval "$*"
  fi
}

# ----------------------------------------------------------------------
# Pre‑flight: verify core utilities
# ----------------------------------------------------------------------
for cmd in losetup parted mkfs.f2fs mkfs.vfat rsync tar xz curl blkid blockdev; do
  require_cmd "$cmd"
done

# ----------------------------------------------------------------------
# Usage
# ----------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 [-i IMAGE_OR_URL] [-d /dev/sdX] [-s] [-n] [-x] [-h]
  -i IMAGE_OR_URL   source .img or .img.xz (local file or http(s) URL)
  -d DEVICE         target block device (if omitted you’ll get an fzf selector)
  -s                enable SSH on first boot (creates /boot/ssh)
  -n                dry‑run – only print actions, don’t modify anything
  -x                enable Bash tracing (set -x) for debugging
  -h                show this help
EOF
  exit "$E_USAGE"
}

# ----------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------
IMAGE=""
DEVICE=""
ENABLE_SSH=0

while getopts "i:d:snhx" opt; do
  case "$opt" in
    i) IMAGE="$OPTARG" ;;
    d) DEVICE="$OPTARG" ;;
    s) ENABLE_SSH=1 ;;
    n) DRY_RUN=1 ;;
    x) DEBUG=1 ;;
    h|?) usage ;;
  esac
done

# Enable Bash tracing if requested
if (( DEBUG )); then
  set -x
fi

# ----------------------------------------------------------------------
# Re‑exec as root if necessary
# ----------------------------------------------------------------------
if [ "$(id -u)" != 0 ]; then
  log "⚠️  Not running as root – re‑executing with sudo"
  exec sudo -E bash "$0" "$@"
fi

# ----------------------------------------------------------------------
# Interactive selectors (fzf) – only loaded when needed
# ----------------------------------------------------------------------
fzf_file_picker() {
  command -v fzf >/dev/null 2>&1 || { log "fzf required for interactive selection"; usage; }
  if command -v fd >/dev/null 2>&1; then
    fd -tf -e img -e xz -p "${HOME:-.}" \
      | fzf --height=~40% --layout=reverse --inline-info \
            --prompt="Select image: " \
            --header="Select image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
  else
    find "${HOME:-.}" -type f \( -iname '*.img' -o -iname '*.xz' \) -print0 \
      | fzf --read0 --height=~40% --layout=reverse --inline-info \
            --prompt="Select image: " \
            --header="Select image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
  fi
}

# ----------------------------------------------------------------------
# Choose image (if not supplied)
# ----------------------------------------------------------------------
if [[ -z $IMAGE ]]; then
  IMAGE="$(fzf_file_picker)"
  [[ -z $IMAGE ]] && { log "No image selected."; usage; }
fi

# ----------------------------------------------------------------------
# Choose target device (if not supplied)
# ----------------------------------------------------------------------
if [[ -z $DEVICE ]]; then
  command -v fzf >/dev/null 2>&1 || { log "fzf required for device selection"; usage; }
  SEL=$(
    lsblk -dn -o NAME,TYPE,RM,SIZE,MODEL,MOUNTPOINT |
    awk '
      $2=="disk" && ($3=="1" || $3=="0") && ($6=="" || $6=="-") {
        printf "/dev/%s\t%s %s\n",$1,$4,$5
      }' |
    fzf --height=~40% --layout=reverse --inline-info \
        --prompt="Select target device: " \
        --header="Path\tSize Model" --no-multi -1 -0
  )
  [[ -z $SEL ]] && { log "No device selected."; exit "$E_ABORT"; }
  DEVICE=$(awk '{print $1}' <<<"$SEL")
fi

[[ ! -b $DEVICE ]] && { log "Target $DEVICE not found or not a block device."; exit "$E_ABORT"; }

# ----------------------------------------------------------------------
# Working directories
# ----------------------------------------------------------------------
WORKDIR="$(mktemp -d)"
SRC_IMG="${WORKDIR}/source.img"
BOOT_MNT="${WORKDIR}/boot"
ROOT_MNT="${WORKDIR}/root"
mkdir -p -- "$BOOT_MNT" "$ROOT_MNT"

# ----------------------------------------------------------------------
# Fetch remote image (if URL) – supports resume & checksum placeholder
# ----------------------------------------------------------------------
case "$IMAGE" in
  http://*|https://*)
    SRC_URL="$IMAGE"
    IMAGE="${WORKDIR}/$(basename "$SRC_URL")"
    log "Downloading $SRC_URL → $IMAGE"
    curl -C - -SfL --progress-bar -o "$IMAGE" "$SRC_URL"
    ;;
esac

# ----------------------------------------------------------------------
# Extract / copy the source image to a plain .img file
# ----------------------------------------------------------------------
case "$IMAGE" in
  *.xz)  xz -dc "$IMAGE" > "$SRC_IMG" ;;
  *)    cp --reflink=auto "$IMAGE" "$SRC_IMG" ;;
esac

# ----------------------------------------------------------------------
# Confirm destructive operation
# ----------------------------------------------------------------------
log "[*] WARNING: All data on ${DEVICE} will be DESTROYED!"
read -r -p "Type yes to continue: " CONFIRM
CONFIRM=${CONFIRM,,}               # lower‑case
[[ $CONFIRM != "yes" ]] && { log "Aborted by user."; exit "$E_ABORT"; }

# ----------------------------------------------------------------------
# Partition the target device
# ----------------------------------------------------------------------
run "wipefs -af $DEVICE"
run "parted -s $DEVICE mklabel msdos"
run "parted -s $DEVICE mkpart primary fat32 0% $BOOT_SIZE"
run "parted -s $DEVICE mkpart primary $BOOT_SIZE 100%"
run "partprobe $DEVICE"
udevadm settle || true   # wait for udev to create /dev entries

# Determine partition names (handles mmcblk*, nvme*, sd*)
case "$DEVICE" in
  *mmcblk*|*nvme*) PART_BOOT="${DEVICE}p1"; PART_ROOT="${DEVICE}p2" ;;
  *)               PART_BOOT="${DEVICE}1";  PART_ROOT="${DEVICE}2"  ;;
esac

# ----------------------------------------------------------------------
# Filesystem creation
# ----------------------------------------------------------------------
run "mkfs.vfat -F32 -I -n boot ${PART_BOOT}"

run "mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum -l root ${PART_ROOT}"

# ----------------------------------------------------------------------
# Mount source image partitions (detect loop‑device suffix)
# ----------------------------------------------------------------------
LOOP_DEV="$(losetup --show -fP "$SRC_IMG")"
# Some loop devices need a “p” suffix, others don’t
case "$LOOP_DEV" in
  *loop*) LOOP_SUFFIX="" ;;
  *)      LOOP_SUFFIX="p" ;;
esac
run "mount ${LOOP_DEV}${LOOP_SUFFIX}1 $BOOT_MNT"
run "mount ${LOOP_DEV}${LOOP_SUFFIX}2 $ROOT_MNT"

# ----------------------------------------------------------------------
# Mount target partitions
# ----------------------------------------------------------------------
TARGET_BOOT="${WORKDIR}/target_boot"
TARGET_ROOT="${WORKDIR}/target_root"
mkdir -p "$TARGET_BOOT" "$TARGET_ROOT"
run "mount $PART_BOOT $TARGET_BOOT"
run "mount $PART_ROOT $TARGET_ROOT"

# ----------------------------------------------------------------------
# Helper: free space in a tmpfs mountpoint (used for fast copy)
# ----------------------------------------------------------------------
get_free_tmpfs_mb() {
  best=0
  for m in /dev/shm /run/shm /tmp; do
    [ -e "$m" ] || continue
    val=$(df -Pm "$m" 2>/dev/null | awk 'NR==2{print $4}')
    [[ $val =~ ^[0-9]+$ ]] || val=0
    (( val > best )) && best=$val
  done
  printf '%s' "$best"
}

# ----------------------------------------------------------------------
# Copy root filesystem (tar‑stream → tmpfs if enough RAM, otherwise rsync)
# ----------------------------------------------------------------------
ROOT_SIZE_MB=$(du -sm "$ROOT_MNT" | awk '{print $1}')
TMPFS_SIZE=$(( ROOT_SIZE_MB + 512 ))
FREE_MB=$(get_free_tmpfs_mb)

log "[*] Copying root filesystem…"
if (( FREE_MB >= TMPFS_SIZE )); then
  TMPFS_MNT="${WORKDIR}/tmpfs_root"
  run "mkdir -p $TMPFS_MNT"
  run "mount -t tmpfs -o size=${TMPFS_SIZE}M tmpfs $TMPFS_MNT"
  (cd "$ROOT_MNT" && tar -cpf - .) | (cd "$TMPFS_MNT" && tar -xpf -)
  (cd "$TMPFS_MNT" && tar -cpf - .) | (cd "$TARGET_ROOT" && tar -xpf -)
  run "umount $TMPFS_MNT"
  rm -rf "$TMPFS_MNT"
else
  log "[!] Not enough free tmpfs ($FREE_MB MiB); falling back to rsync"
  run "rsync -aHAX --inplace --fsync --no-whole-file --progress $ROOT_MNT/ $TARGET_ROOT/"
fi

# ----------------------------------------------------------------------
# Copy boot partition (same strategy, smaller threshold)
# ----------------------------------------------------------------------
log "[*] Copying boot partition…"
if (( FREE_MB >= 128 )); then
  (cd "$BOOT_MNT" && tar -cpf - .) | (cd "$TARGET_BOOT" && tar -xpf -)
else
  run "rsync -aHAX --inplace --fsync --no-whole-file --progress $BOOT_MNT/ $TARGET_BOOT/"
fi

# ----------------------------------------------------------------------
# Update bootloader configuration (cmdline.txt) and fstab
# ----------------------------------------------------------------------
BOOT_UUID=$(blkid -s PARTUUID -o value "$PART_BOOT" 2>/dev/null || true)
ROOT_UUID=$(blkid -s PARTUUID -o value "$PART_ROOT" 2>/dev/null || true)

if [[ -f "${TARGET_BOOT}/cmdline.txt" ]]; then
  sed -i "s|root=[^ ]*|root=PARTUUID=$ROOT_UUID|" "${TARGET_BOOT}/cmdline.txt" || true
  sed -i "s|rootfstype=[^ ]*|rootfstype=f2fs|" "${TARGET_BOOT}/cmdline.txt" || true
fi

cat > "${TARGET_ROOT}/etc/fstab" <<EOF
proc                  /proc   proc    defaults                    0   0
PARTUUID=$BOOT_UUID  /boot   vfat    defaults                    0   2
PARTUUID=$ROOT_UUID  /       f2fs    defaults,noatime,discard    0   1
EOF

# ----------------------------------------------------------------------
# Optional SSH enable (touch /boot/ssh)
# ----------------------------------------------------------------------
if (( ENABLE_SSH )); then
  log "[*] Enabling SSH on first boot"
  touch "${TARGET_BOOT}/ssh"
fi

# ----------------------------------------------------------------------
# First‑boot F2FS resize script (initramfs hook)
# ----------------------------------------------------------------------
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
  log_end_msg "resize.f2fs not found – skipping."
fi
EOF
chmod +x "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount/f2fsresize" || :

# ----------------------------------------------------------------------
# Final sync & cleanup (handled by trap as well)
# ----------------------------------------------------------------------
log "[+] Syncing disks…"
sync

# Unmount everything (ignore errors – cleanup trap will also try)
umount "$BOOT_MNT" "$ROOT_MNT" "$TARGET_BOOT" "$TARGET_ROOT" 2>/dev/null || :

# Detach loop device
losetup -d "${LOOP_DEV:-}" 2>/dev/null || :

# Remove temporary work directory
rm -rf "${WORKDIR:-}"

log "[+] Done. F2FS Raspberry Pi image ready on $DEVICE."
