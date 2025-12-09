#!/usr/bin/env bash
# Build and install Raspberry Pi kernel from source
# WARNING: This script will reboot the system after kernel installation
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C DEBIAN_FRONTEND=noninteractive
export HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}"

# Colors
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' DEF=$'\e[0m'

# Helpers
has() { command -v "$1" &>/dev/null; }
log() { printf '%s\n' "${BLU}→${DEF} $*"; }
warn() { printf '%s\n' "${YLW}WARN:${DEF} $*"; }
err() { printf '%s\n' "${RED}ERROR:${DEF} $*" >&2; }
die() {
  err "$*"
  exit "${2:-1}"
}

confirm() {
  local prompt=${1:-"Continue?"} default=${2:-n}
  local yn
  read -rp "$prompt [y/N] " yn
  [[ ${yn,,} == y* ]]
}

# Config
KERNEL_BRANCH=${KERNEL_BRANCH:-rpi-6.16.y}
KERNEL_SRC=${KERNEL_SRC:-/usr/src/linux}

usage() {
  cat <<EOF
Usage: Kbuild.sh [OPTIONS]

Build and install Raspberry Pi kernel from source.

Options:
  -b, --branch BRANCH  Kernel branch (default: $KERNEL_BRANCH)
  -y, --yes            Skip confirmation prompts
  -h, --help           Show this help

Environment:
  KERNEL_BRANCH  Kernel branch to build (default: rpi-6.16.y)
  KERNEL_SRC     Kernel source directory (default: /usr/src/linux)

WARNING: This script will reboot after installation!
EOF
  exit 0
}

# Parse args
ASSUME_YES=0
while (($#)); do
  case "$1" in
    -b | --branch)
      KERNEL_BRANCH=${2:?}
      shift
      ;;
    -y | --yes) ASSUME_YES=1 ;;
    -h | --help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

main() {
  log "Raspberry Pi Kernel Build - branch: $KERNEL_BRANCH"

  # Require root
  ((EUID == 0)) || die "Must run as root"

  # Confirm destructive operation
  if ((!ASSUME_YES)); then
    warn "This will build and install a new kernel, then REBOOT!"
    confirm "Proceed with kernel build?" || {
      log "Aborted"
      exit 0
    }
  fi

  # Install build dependencies
  log "Installing build dependencies..."
  apt-get update -y
  apt-get install -y --no-install-recommends \
    bc bison cpio flex git kmod \
    build-essential ca-certificates \
    libncurses-dev libssl-dev rsync

  # Clone kernel source
  if [[ -d $KERNEL_SRC/.git ]]; then
    log "Updating existing kernel source..."
    git -C "$KERNEL_SRC" fetch --depth=1 origin "$KERNEL_BRANCH"
    git -C "$KERNEL_SRC" checkout FETCH_HEAD
  else
    log "Cloning kernel source..."
    rm -rf "$KERNEL_SRC"
    git clone --depth=1 --filter=blob:none --branch "$KERNEL_BRANCH" \
      https://github.com/raspberrypi/linux "$KERNEL_SRC"
  fi

  cd "$KERNEL_SRC"

  # Configure and build
  log "Configuring kernel..."
  make bcm2711_defconfig

  log "Building kernel (this will take a while)..."
  make -j"$(nproc)" Image.gz modules dtbs

  log "Installing modules..."
  make modules_install

  # Install kernel and device trees
  log "Installing kernel..."
  cp arch/arm64/boot/dts/broadcom/*.dtb /boot/
  cp arch/arm64/boot/dts/overlays/*.dtb* /boot/overlays/
  cp arch/arm64/boot/dts/overlays/README /boot/overlays/
  cp arch/arm64/boot/Image.gz /boot/kernel8.img

  # Update bootloader config (avoid duplicate entry)
  if ! grep -q '^dtoverlay=vc4-kms-v3d' /boot/config.txt 2>/dev/null; then
    log "Adding dtoverlay to config.txt..."
    echo "dtoverlay=vc4-kms-v3d" >>/boot/config.txt
  fi

  log "${GRN}Kernel installed successfully${DEF}"

  # Reboot with countdown
  warn "Rebooting in 10 seconds... (Ctrl+C to cancel)"
  sleep 10
  systemctl reboot -q || reboot
}

main "$@"
