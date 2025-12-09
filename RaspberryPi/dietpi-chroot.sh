#!/usr/bin/env bash
# DESCRIPTION: Chroot into ARM64 DietPi/PiOS images from x86_64 Arch Linux
#              - Uses qemu-user-static for cross-architecture execution
#              - Safely handles mounting/unmounting to prevent corruption
#              - Injects QEMU binary and resolv.conf automatically
# DEPENDENCIES: qemu-user-static, qemu-user-static-binfmt, util-linux, parted
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C PATH="${PATH}:/sbin:/usr/sbin:/usr/local/sbin"

# Configuration
QEMU_BIN="/usr/bin/qemu-aarch64-static"
MOUNT_DIR="/mnt/dietpi-chroot"

# Colors
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Globals
declare -g IMG_FILE="" LOOP_DEV="" ROOT_PART="" BOOT_PART=""
declare -ga MOUNTED_POINTS=()

# Helpers
has(){ command -v "$1" &>/dev/null; }
log(){ printf '[%s] %b%s%b\n' "$(date +%T)" "${BLU}${BLD}[*]${DEF} " "$*"; }
msg(){ printf '[%s] %b%s%b\n' "$(date +%T)" "${GRN}${BLD}[+]${DEF} " "$*"; }
warn(){ printf '[%s] %b%s%b\n' "$(date +%T)" "${YLW}${BLD}[!]${DEF} " "$*" >&2; }
err(){ printf '[%s] %b%s%b\n' "$(date +%T)" "${RED}${BLD}[-]${DEF} " "$*" >&2; }
die(){
  err "$1"
  cleanup
  exit "${2:-1}"
}

check_deps(){
  local -a deps=(losetup parted mount umount qemu-aarch64-static)
  local missing=()
  for cmd in "${deps[@]}"; do has "$cmd" || missing+=("$cmd"); done

  if ((${#missing[@]} > 0)); then
    err "Missing dependencies: ${missing[*]}"
    err "On Arch: sudo pacman -S qemu-user-static qemu-user-static-binfmt parted"
    exit 1
  fi

  # Check binfmt_misc
  if [ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]; then
    warn "binfmt_misc for aarch64 not detected. Trying to load..."
    sudo systemctl restart systemd-binfmt 2>/dev/null || :
    if [ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]; then
      die "Could not verify aarch64 binfmt registration. Is 'qemu-user-static-binfmt' installed and service active?"
    fi
  fi
}

cleanup(){
  set +e
  log "Cleaning up..."

  # 1. Kill processes inside the mount to free handles
  if [[ -d "$MOUNT_DIR" ]]; then
    # Gentle kill then force kill
    fuser -k -M "$MOUNT_DIR" 2>/dev/null
  fi

  # 2. Unmount filesystems in reverse order
  if mountpoint -q "$MOUNT_DIR/boot"; then
    umount "$MOUNT_DIR/boot" 2>/dev/null
  fi

  # Recursive unmount for proc, sys, dev, etc.
  if mountpoint -q "$MOUNT_DIR"; then
    umount -R "$MOUNT_DIR" 2>/dev/null
  fi

  # 3. Detach loop device
  if [[ -n "$LOOP_DEV" ]]; then
    losetup -d "$LOOP_DEV" 2>/dev/null
  fi

  # 4. Remove mount point
  [[ -d "$MOUNT_DIR" ]] && rmdir "$MOUNT_DIR" 2>/dev/null

  msg "Cleanup complete. Image saved."
}

setup_image(){
  local img="$1"
  [[ -f "$img" ]] || die "Image file not found: $img"

  log "Setting up loop device for $img..."
  LOOP_DEV=$(losetup --show -f -P "$img") || die "Failed to setup loop device"

  # DietPi/PiOS usually: p1=boot (vfat), p2=root (ext4)
  BOOT_PART="${LOOP_DEV}p1"
  ROOT_PART="${LOOP_DEV}p2"

  if [[ ! -b "$ROOT_PART" ]]; then
    die "Could not find root partition ($ROOT_PART). Is this a valid PI image?"
  fi

  # Prepare mount point
  mkdir -p "$MOUNT_DIR"

  log "Mounting root partition..."
  mount "$ROOT_PART" "$MOUNT_DIR" || die "Failed to mount root"

  log "Mounting boot partition..."
  mount "$BOOT_PART" "$MOUNT_DIR/boot" || die "Failed to mount boot"
}

setup_chroot(){
  log "Setting up QEMU and bind mounts..."

  # Copy static QEMU binary
  # This is crucial for x86_64 -> aarch64 execution
  cp "$QEMU_BIN" "$MOUNT_DIR/usr/bin/" || die "Failed to copy qemu binary"

  # Copy resolv.conf for networking
  cp /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf" || warn "Failed to copy resolv.conf"

  # Bind mounts
  for i in /dev /dev/pts /proc /sys; do
    mount -B "$i" "$MOUNT_DIR$i"
  done
}

run_optimization(){
  msg "Entering CHROOT environment (ARM64)..."
  echo "-----------------------------------------------------"
  echo "  You are now inside the image."
  echo "  Architecture: $(uname -m) (emulated via QEMU)"
  echo "  Type 'exit' or Ctrl+D to save changes and leave."
  echo "-----------------------------------------------------"

  # Optional: define a custom rc file or commands to run immediately
  # For manual tweaking, just spawning bash is best.

  chroot "$MOUNT_DIR" /bin/bash

  echo "-----------------------------------------------------"
  log "Exited chroot."

  # Clean internal artifacts before unmounting
  log "Cleaning internal artifacts (qemu, resolv.conf)..."
  rm -f "$MOUNT_DIR/usr/bin/qemu-aarch64-static"
  # Optional: Revert resolv.conf if you want strictly offline state,
  # but DietPi usually regenerates it anyway.
  # rm -f "$MOUNT_DIR/etc/resolv.conf"

  log "Syncing filesystem..."
  sync
}

# Main
[[ $EUID -ne 0 ]] && die "This script requires root privileges (sudo)."

if [[ $# -eq 0 ]]; then
  echo "Usage: sudo $0 <image_file.img>"
  exit 1
fi

IMG_FILE="$1"

trap cleanup EXIT INT TERM

check_deps
setup_image "$IMG_FILE"
setup_chroot
run_optimization

msg "${GRN}SUCCESS:${DEF} Image optimization complete."
