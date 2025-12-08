#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}" DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
# WARNING: This script will reboot the system after kernel installation
has() { command -v -- "$1" &> /dev/null; }
find_with_fallback() {
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2> /dev/null || shift $#
  if has fd; then
    fd -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"
  elif has fdfind; then
    fdfind -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"
  else
    local find_type_arg
    case "$ftype" in
      f) find_type_arg="-type f" ;;
      d) find_type_arg="-type d" ;;
      l) find_type_arg="-type l" ;;
      *) find_type_arg="-type f" ;;
    esac
    [[ -n $action ]] && find "$search_path" $find_type_arg -name "$pattern" "$action" "$@" || find "$search_path" $find_type_arg -name "$pattern"
  fi
}
sudo apt-get update -y && sudo apt-get install -y --no-install-recommends \
  bc bison cpio flex git kmod \
  build-essential ca-certificates \
  libncurses-dev libssl-dev rsync
# Clone the repository
git clone --depth=1 --filter=blob:none --branch rpi-6.16.y https://github.com/raspberrypi/linux /usr/src/linux
# Configure and build
cd /usr/src/linux
make bcm2711_defconfig
make -j"$(nproc)" Image.gz modules dtbs
make modules_install
# Install the kernel
cp arch/arm64/boot/dts/broadcom/*.dtb /boot/
cp arch/arm64/boot/dts/overlays/*.dtb* /boot/overlays/
cp arch/arm64/boot/dts/overlays/README /boot/overlays/
cp arch/arm64/boot/Image.gz /boot/kernel8.img
# Update the bootloader
echo "dtoverlay=vc4-kms-v3d" >> /boot/config.txt
# Reboot
printf '%s\n' "Rebooting in 10 seconds..."
sleep 10
sudo systemctl reboot -q || sudo reboot
