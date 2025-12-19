#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
s=${BASH_SOURCE[0]}
[[ $s != /* ]] && s=$PWD/$s
cd -P -- "${s%/*}"
# DESCRIPTION: Chroot into ARM64 DietPi/PiOS images from x86_64 Arch Linux
#              - Uses qemu-user-static for cross-architecture execution
#              - Safely handles mounting/unmounting to prevent corruption
#              - Injects QEMU binary and resolv.conf automatically
#              - Optional PiShrink integration for image optimization
# DEPENDENCIES: qemu-user-static, qemu-user-static-binfmt, util-linux, parted, e2fsck, resize2fs
# Configuration
QEMU_BIN="/usr/bin/qemu-aarch64-static"
MOUNT_DIR="/mnt/dietpi-chroot"
# Colors
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
DEF=$'\e[0m' BLD=$'\e[1m'
# Globals
declare -g IMG_FILE="" LOOP_DEV="" ROOT_PART="" BOOT_PART="" SHRINK=0
declare -ga MOUNTED_POINTS=()
# Helpers
fdate(){
  printf '%(%T)T\n' '-1'
}
log(){ printf '[%s] %b%s\n' "$(fdate)" "${BLU}${BLD}[*]${DEF} " "$*"; }
msg(){ printf '[%s] %b%s\n' "$(fdate)" "${GRN}${BLD}[+]${DEF} " "$*"; }
warn(){ printf '[%s] %b%s\n' "$(fdate)" "${YLW}${BLD}[!]${DEF} " "$*" >&2; }
err(){ printf '[%s] %b%s\n' "$(fdate)" "${RED}${BLD}[-]${DEF} " "$*" >&2; }
die(){ err "$1"; cleanup; exit "${2:-1}"; }

check_deps(){
  local -a deps=(losetup parted mount umount qemu-aarch64-static)
  ((SHRINK)) && deps+=(e2fsck resize2fs tune2fs truncate)
  local -a missing=() cmd
  for cmd in "${deps[@]}"; do
    if ! command -v -- "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  ((${#missing[@]} > 0)) && {
    err "Missing dependencies: ${missing[*]}"
    err "On Arch: sudo pacman -S qemu-user-static qemu-user-static-binfmt parted e2fsprogs"
    exit 1
  }
  [[ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]] && {
    warn "binfmt_misc for aarch64 not detected. Trying to load..."
    sudo systemctl restart systemd-binfmt &>/dev/null || :
    [[ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]] && die "Could not verify aarch64 binfmt registration. Is 'qemu-user-static-binfmt' installed and service active?"
  }
}
cleanup(){
  set +e
  log "Cleaning up..."
  [[ -d $MOUNT_DIR ]] && fuser -k -M "$MOUNT_DIR" &>/dev/null
  mountpoint -q "$MOUNT_DIR/boot" && umount "$MOUNT_DIR/boot" &>/dev/null
  mountpoint -q "$MOUNT_DIR" && umount -R "$MOUNT_DIR" &>/dev/null
  [[ -n $LOOP_DEV ]] && losetup -d "$LOOP_DEV" &>/dev/null
  [[ -d $MOUNT_DIR ]] && rmdir "$MOUNT_DIR" &>/dev/null
  msg "Cleanup complete. Image saved."
}
setup_image(){
  local img="$1"
  [[ -f $img ]] || die "Image file not found: $img"
  log "Setting up loop device for $img..."
  LOOP_DEV=$(losetup --show -f -P "$img") || die "Failed to setup loop device"
  BOOT_PART="${LOOP_DEV}p1"
  ROOT_PART="${LOOP_DEV}p2"
  [[ ! -b $ROOT_PART ]] && die "Could not find root partition ($ROOT_PART). Is this a valid PI image?"
  mkdir -p "$MOUNT_DIR"
  log "Mounting root partition..."
  mount "$ROOT_PART" "$MOUNT_DIR" || die "Failed to mount root"
  log "Mounting boot partition..."
  mount "$BOOT_PART" "$MOUNT_DIR/boot" || die "Failed to mount boot"
}
setup_chroot(){
  log "Setting up QEMU and bind mounts..."
  cp "$QEMU_BIN" "$MOUNT_DIR/usr/bin/" || die "Failed to copy qemu binary"
  cp /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf" || warn "Failed to copy resolv.conf"
  for i in /dev /dev/pts /proc /sys; do mount -B "$i" "$MOUNT_DIR$i"; done
}
check_filesystem(){
  log "Checking filesystem..."
  e2fsck -pf "$ROOT_PART"
  (($? < 4)) && return
  warn "Filesystem error detected! Attempting recovery..."
  e2fsck -y "$ROOT_PART"
  (($? < 4)) && return
  e2fsck -fy -b 32768 "$ROOT_PART"
  (($? < 4)) && return
  die "Filesystem recovery failed."
}
shrink_image(){
  log "Shrinking image..."
  umount -R "$MOUNT_DIR" &>/dev/null
  losetup -d "$LOOP_DEV" &>/dev/null
  local parted_out partnum partstart parttype currentsize blocksize minsize extra_space partnewsize newpartend endresult
  parted_out=$(parted -ms "$IMG_FILE" unit B print) || die "parted failed"
  partnum=$(awk -F: 'END{print $1}' <<<"$parted_out")
  partstart=$(awk -F: 'END{print $2}' <<<"$parted_out" | tr -d B)
  if parted -s "$IMG_FILE" unit B print | grep -q "$partstart" | grep -q logical; then
    parttype="logical"
  else
    parttype="primary"
  fi
  LOOP_DEV=$(losetup -f --show -o "$partstart" "$IMG_FILE") || die "Failed to setup loop device"
  check_filesystem
  local tune_out
  tune_out=$(tune2fs -l "$LOOP_DEV") || die "tune2fs failed"
  currentsize=$(awk -F: '/^Block count:/{gsub(" ","",$2);print $2}' <<<"$tune_out")
  blocksize=$(awk -F: '/^Block size:/{gsub(" ","",$2);print $2}' <<<"$tune_out")
  minsize=$(resize2fs -P "$LOOP_DEV" 2>&1 | awk -F: '{gsub(" ","",$2);print $2}') || die "resize2fs -P failed"
  [[ $currentsize -eq $minsize ]] && {
    log "Filesystem already at minimum size"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }
  extra_space=$((currentsize - minsize))
  for space in 5000 1000 100; do ((extra_space > space)) && {
    minsize=$((minsize + space))
    break
  }; done
  log "Resizing filesystem to ${minsize} blocks..."
  resize2fs -p "$LOOP_DEV" "$minsize" || die "resize2fs failed"
  local mnt
  mnt=$(mktemp -d)
  mount "$LOOP_DEV" "$mnt"
  log "Zeroing free space..."
  cat /dev/zero >"$mnt/zero_file" 2>&1 || :
  rm -f "$mnt/zero_file"
  umount "$mnt"
  rmdir "$mnt"
  partnewsize=$((minsize * blocksize))
  newpartend=$((partstart + partnewsize))
  log "Shrinking partition..."
  parted -s -a minimal "$IMG_FILE" rm "$partnum" || die "parted rm failed"
  parted -s "$IMG_FILE" unit B mkpart "$parttype" "$partstart" "$newpartend" || die "parted mkpart failed"
  losetup -d "$LOOP_DEV" &>/dev/null
  endresult=$(parted -ms "$IMG_FILE" unit B print free | tail -1 | awk -F: '{print $2}' | tr -d B)
  log "Truncating image to ${endresult}B..."
  truncate -s "$endresult" "$IMG_FILE" || die "truncate failed"
  msg "Image shrunk successfully"
}
run_optimization(){
  msg "Entering CHROOT environment (ARM64)..."
  printf '%s\n' "-----------------------------------------------------" \
    "  You are now inside the image." \
    "  Architecture: $(uname -m) (emulated via QEMU)" \
    "  Type 'exit' or Ctrl+D to save changes and leave." \
    "-----------------------------------------------------"
  chroot "$MOUNT_DIR" /bin/bash
  printf '%s\n' "-----------------------------------------------------"
  log "Exited chroot."
  log "Cleaning internal artifacts..."
  rm -f "$MOUNT_DIR/usr/bin/qemu-aarch64-static"
  log "Syncing filesystem..."
  sync
}
usage(){
  cat <<-'EOF'
	Usage: sudo $0 [OPTIONS] <image_file.img>
	OPTIONS:
	  -z    Shrink image after chroot (PiShrink integration)
	  -h    Show this help
EOF
  exit 0
}
while getopts "zh" opt; do
  case $opt in
    z) SHRINK=1 ;; h) usage ;; *) usage ;;
  esac
done
shift $((OPTIND - 1))
[[ $EUID -ne 0 ]] && die "This script requires root privileges (sudo)."
[[ $# -eq 0 ]] && usage
IMG_FILE="$1"
trap cleanup EXIT INT TERM
check_deps
setup_image "$IMG_FILE"
setup_chroot
run_optimization
((SHRINK)) && shrink_image
msg "${GRN}SUCCESS:${DEF} Image optimization complete."
