#!/usr/bin/env bash
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ============ Inlined from lib/common.sh ============
export LC_ALL=C LANG=C
export DEBIAN_FRONTEND=noninteractive
export HOME="/home/${SUDO_USER:-$USER}"
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'
	'
has() { command -v -- "$1" &>/dev/null; }
hasname() { local x; if ! x=$(type -P -- "$1"); then return 1; fi; printf '%s
' "${x##*/}"; }
is_program_installed() { command -v "$1" &>/dev/null; }
get_workdir() { local script="${BASH_SOURCE[1]:-$0}"; builtin cd -- "$(dirname -- "$script")" && printf '%s
' "$PWD"; }
init_workdir() { local workdir; workdir="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[1]:-}")" && printf '%s
' "$PWD")"; cd "$workdir" || { echo "Failed to change to working directory: $workdir" >&2; exit 1; }; }
require_root() { if [[ $EUID -ne 0 ]]; then local script_path; script_path=$([[ ${BASH_SOURCE[1]:-$0} == /* ]] && echo "${BASH_SOURCE[1]:-$0}" || echo "$PWD/${BASH_SOURCE[1]:-$0}"); sudo "$script_path" "$@" || { echo 'Administrator privileges are required.' >&2; exit 1; }; exit 0; fi; }
check_root() { if [[ $EUID -ne 0 ]]; then echo "This script must be run as root." >&2; exit 1; fi; }
load_dietpi_globals() { [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :; }
run_dietpi_cleanup() { if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then if ! sudo dietpi-update 1 && ! sudo /boot/dietpi/dietpi-update 1; then echo "Warning: dietpi-update failed (both standard and fallback commands)." >&2; fi; sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null || :; sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null || :; fi; }
setup_environment() { set -euo pipefail; shopt -s nullglob globstar execfail; IFS=$'
	'; }
get_sudo_cmd() { local sudo_cmd; sudo_cmd="$(hasname sudo-rs || hasname sudo || hasname doas)" || { echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; return 1; }; printf '%s
' "$sudo_cmd"; }
init_sudo() { local sudo_cmd; sudo_cmd="$(get_sudo_cmd)" || return 1; if [[ $EUID -ne 0 && $sudo_cmd =~ ^(sudo-rs|sudo)$ ]]; then "$sudo_cmd" -v 2>/dev/null || :; fi; }
find_with_fallback() { local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"; shift 4 2>/dev/null || shift $#; if has fdf; then fdf -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"; elif has fd; then fd -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"; else local find_type_arg; case "$ftype" in f) find_type_arg="-type f" ;; d) find_type_arg="-type d" ;; l) find_type_arg="-type l" ;; *) find_type_arg="-type f" ;; esac; if [[ -n $action ]]; then find "$search_path" $find_type_arg -name "$pattern" "$action" "$@"; else find "$search_path" $find_type_arg -name "$pattern"; fi; fi; }
# ============ End of inlined lib/common.sh ============

# Setup environment
setup_environment

# Build and install a custom Raspberry Pi kernel.
# Ensure we're running as root
check_root
# Install dependencies
apt-get update && apt-get install -y --no-install-recommends \
  bc bison cpio flex git kmod \
  build-essential ca-certificates \
  libncurses-dev libssl-dev rsync
# Clone the repository
git clone --depth=1 --filter=blob:none --branch rpi-6.16.y https://github.com/raspberrypi/linux /usr/src/linux
# Configure the build
cd /usr/src/linux
make bcm2711_defconfig
# Build the kernel and modules
make -j"$(nproc)" Image.gz modules dtbs
# Install the modules
make modules_install
# Install the kernel
cp arch/arm64/boot/dts/broadcom/*.dtb /boot/
cp arch/arm64/boot/dts/overlays/*.dtb* /boot/overlays/
cp arch/arm64/boot/dts/overlays/README /boot/overlays/
cp arch/arm64/boot/Image.gz /boot/kernel8.img
# Update the bootloader
echo "dtoverlay=vc4-kms-v3d" >>/boot/config.txt
# Reboot
echo "Rebooting in 10 seconds..."
sleep 10
sudo systemctl reboot -q || sudo reboot
