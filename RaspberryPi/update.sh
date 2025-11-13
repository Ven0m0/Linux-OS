#!/usr/bin/env bash

# Setup environment
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'

# Initialize working directory
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKDIR" || {
  echo "Failed to change to working directory: $WORKDIR" >&2
  exit 1
}

# Color constants for terminal output
LBLU=$'\e[38;5;117m'
PNK=$'\e[38;5;218m'
BWHT=$'\e[97m'
DEF=$'\e[0m'

# Check if a command exists
has() {
  command -v -- "$1" &>/dev/null
}

# Display colorized banner with gradient effect
display_banner() {
  local banner_text="$1"
  shift
  local -a flag_colors=("$@")

  mapfile -t banner_lines <<<"$banner_text"
  local lines=${#banner_lines[@]}
  local segments=${#flag_colors[@]}

  if ((lines <= 1)); then
    for line in "${banner_lines[@]}"; do
      printf "%s%s%s\n" "${flag_colors[0]}" "$line" "$DEF"
    done
  else
    for i in "${!banner_lines[@]}"; do
      local segment_index=$((i * (segments - 1) / (lines - 1)))
      ((segment_index >= segments)) && segment_index=$((segments - 1))
      printf "%s%s%s\n" "${flag_colors[segment_index]}" "${banner_lines[i]}" "$DEF"
    done
  fi
}

# Clean APT package manager cache
clean_apt_cache() {
  sudo apt-get clean -yq
  sudo apt-get autoclean -yq
  sudo apt-get autoremove --purge -yq
}

# Load DietPi globals if available
load_dietpi_globals() {
  [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :
}

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
