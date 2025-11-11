#!/usr/bin/env bash
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/cleaning.sh"
source "${SCRIPT_DIR}/lib/text.sh"

# Setup environment
setup_environment

# Initialize working directory
init_workdir

#============ Banner ====================
banner=$(
  cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
)
display_banner "$banner" "$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU"
echo "Meow (> ^ <)"
#============ Safety ====================
load_dietpi_globals
sync
#=============================================================
# Clean APT lists before update
sudo rm -rf --preserve-root -- /var/lib/apt/lists/*
export APT_NO_COLOR=1 NO_COLOR=1 DPKG_COLORS=never DEBIAN_FRONTEND=noninteractive
run_apt() {
  sudo apt-get -yqfm --allow-releaseinfo-change -o Acquire::Languages none
  -o APT::Get::Fix-Missing true
  -o APT::Get::Fix-Broken true
  "$1" "$@"
}
if has apt-fast; then
  sudo apt-fast update -yq --allow-releaseinfo-change
  sudo apt-fast upgrade -yfq --no-install-recommends
  sudo apt-fast dist-upgrade -yqf --no-install-recommends
  clean_apt_cache
  sudo apt-fast autopurge -yq 2>/dev/null || :
elif has nala; then
  sudo nala upgrade --no-install-recommends
  sudo nala clean
  sudo nala autoremove
  sudo nala autopurge
  # nala fetch --auto --fetches 5 -c DE -y --non-free --debian --https-only
else
  run_apt update
  run_apt dist-upgrade
  run_apt full-upgrade
  clean_apt_cache
fi
# Check's the broken packages and fix them
sudo dpkg --configure -a >/dev/null

sudo dietpi-update 1 || sudo /boot/dietpi/dietpi-update 1
has pihole && sudo pihole -up
has rpi-eeprom-update && sudo rpi-eeprom-update -a
has rpi-update && sudo SKIP_WARNING=1 PRUNE_MODULES=1 RPI_UPDATE_UNSUPPORTED=0 SKIP_VCLIBS=1 rpi-update
#sudo JUST_CHECK=1 rpi-update
# https://github.com/raspberrypi/rpi-update/blob/master/rpi-update
# Test:
# PRUNE_MODULES=1 SKIP_WARNING=1 RPI_UPDATE_UNSUPPORTED=0

unset LC_ALL
export LANG=C.UTF-8
