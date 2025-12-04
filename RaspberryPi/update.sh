#!/usr/bin/env bash
# Optimized: 2025-11-19 - Applied bash optimization techniques

set -euo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="${HOME:-/home/${SUDO_USER:-$USER}}"
export DEBIAN_FRONTEND=noninteractive

# Colors (trans flag palette)
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m' DEF=$'\e[0m'
export LBLU PNK BWHT DEF

# Core helper functions
has() { command -v -- "$1" &> /dev/null; }

# DietPi functions
load_dietpi_globals() {
  [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &> /dev/null || :
}

# APT functions
clean_apt_cache() {
  sudo apt-get clean -y 2> /dev/null || :
  sudo apt-get autoclean -y 2> /dev/null || :
  sudo apt-get autoremove --purge -y 2> /dev/null || :
}

run_apt() {
  sudo apt-get -y --allow-releaseinfo-change \
    -o Acquire::Languages=none \
    -o APT::Get::Fix-Missing=true \
    -o APT::Get::Fix-Broken=true \
    "$@"
}

# Display colorized banner with gradient effect
display_banner() {
  local banner_text="$1"
  shift
  local -a flag_colors=("$@")
  mapfile -t banner_lines <<< "$banner_text"
  local line_count=${#banner_lines[@]}
  local segments=${#flag_colors[@]}
  if ((line_count <= 1)); then
    for bline in "${banner_lines[@]}"; do
      printf "%s%s%s\n" "${flag_colors[0]}" "$bline" "$DEF"
    done
  else
    for i in "${!banner_lines[@]}"; do
      local segment_index=$((i * (segments - 1) / (line_count - 1)))
      ((segment_index >= segments)) && segment_index=$((segments - 1))
      printf "%s%s%s\n" "${flag_colors[segment_index]}" "${banner_lines[i]}" "$DEF"
    done
  fi
}

export PRUNE_MODULES=1 SKIP_VCLIBS=1

#============ Banner ====================
banner=$(
  cat << 'EOF'
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
if has apt-fast; then
  sudo apt-fast update -y --allow-releaseinfo-change
  sudo apt-fast upgrade -y --no-install-recommends
  sudo apt-fast dist-upgrade -y --no-install-recommends
  clean_apt_cache
  sudo apt-fast autopurge -yq 2> /dev/null || :
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
sudo dpkg --configure -a > /dev/null

sudo dietpi-update 1 || sudo /boot/dietpi/dietpi-update 1
has pihole && sudo pihole -up
has rpi-eeprom-update && sudo rpi-eeprom-update -a
has rpi-update && sudo SKIP_WARNING=1 RPI_UPDATE_UNSUPPORTED=0 PRUNE_MODULES=1 SKIP_VCLIBS=1 rpi-update 2> /dev/null || :
#sudo JUST_CHECK=1 rpi-update
# https://github.com/raspberrypi/rpi-update/blob/master/rpi-update
# Test:
# PRUNE_MODULES=1 SKIP_WARNING=1 RPI_UPDATE_UNSUPPORTED=0
