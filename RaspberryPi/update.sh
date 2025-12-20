#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
# DESCRIPTION: Raspberry Pi system update script for Debian/Raspbian/DietPi
#              Updates: APT packages, DietPi, Pi-hole, firmware (EEPROM/rpi-update)
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C DEBIAN_FRONTEND=noninteractive
# Colors
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m' DEF=$'\e[0m'
# Core helper functions
has() { command -v -- "$1" &>/dev/null; }
usage() {
  cat <<'EOF'
update.sh - Raspberry Pi system update automation

Usage: update.sh [OPTIONS]

Options:
  -h, --help     Show this help message
  --version      Show version

Updates:
  • APT packages (apt-fast/nala/apt-get with optimizations)
  • DietPi system (if installed)
  • Pi-hole (if installed)
  • Raspberry Pi firmware (EEPROM + rpi-update)
  • Automatic cleanup (cache, autoremove, autopurge)

Supported Systems:
  • Raspberry Pi OS (Raspbian)
  • DietPi
  • Debian-based distributions

Examples:
  update.sh              # Full system update
  curl -fsSL <URL> | bash  # One-liner update
EOF
}
# DietPi functions
load_dietpi_globals() {
  if [[ -f /boot/dietpi/func/dietpi-globals ]]; then
    . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :
  fi
}
# APT functions
clean_apt_cache() {
  sudo apt-get clean -y 2>/dev/null || :
  sudo apt-get autoclean -y 2>/dev/null || :
  sudo apt-get autoremove --purge -y 2>/dev/null || :
}
run_apt() {
  yes | sudo apt-get -y --allow-releaseinfo-change --no-install-recommends --no-install-suggests \
    -o Acquire::Languages=none -o APT::Get::Fix-Missing=true \
    -o APT::Get::Fix-Broken=true "$@"
}
# Display colorized banner with gradient effect
display_banner() {
  local banner_text="$1"
  shift
  local -a flag_colors=("$@")
  mapfile -t banner_lines <<<"$banner_text"
  local line_count=${#banner_lines[@]} segments=${#flag_colors[@]}
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
# Parse arguments
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --version)
    printf 'update.sh 1.0.0\n'
    exit 0
    ;;
esac
# Banner
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
printf '%s\n' "Meow (> ^ <)"
# Safety
load_dietpi_globals
sync
# Clean APT lists before update
sudo rm -rf --preserve-root -- /var/lib/apt/lists/*
if command -v -- apt-fast &>/dev/null; then
  set +e
  yes | sudo apt-fast update -y --allow-releaseinfo-change --fix-missing
  yes | sudo apt-fast upgrade -y --no-install-recommends
  yes | sudo apt-fast dist-upgrade -y --no-install-recommends
  set -e
  clean_apt_cache
  sudo apt-fast autopurge -yq &>/dev/null || :
elif command -v -- nala &>/dev/null; then
  yes | sudo nala upgrade --no-install-recommends || :
  sudo nala clean
  sudo nala autoremove
  sudo nala autopurge
else
  yes | sudo apt-get update -y --fix-missing || :
  set +e
  run_apt dist-upgrade
  run_apt full-upgrade
  clean_apt_cache
  set -e
fi
# Check's the broken packages and fix them
sudo dpkg --configure -a &>/dev/null
# Other
if command -v -- dietpi-update &>/dev/null; then
  sudo dietpi-update 1
elif [[ -x /boot/dietpi/dietpi-update ]]; then
  sudo /boot/dietpi/dietpi-update 1
fi
if command -v -- pihole &>/dev/null; then
  yes | sudo pihole -up
fi
if command -v -- rpi-eeprom-update &>/dev/null; then
  sudo rpi-eeprom-update -a
fi
export PRUNE_MODULES=1 SKIP_VCLIBS=1 SKIP_WARNING=1 RPI_UPDATE_UNSUPPORTED=0
if command -v -- rpi-update &>/dev/null; then
  sudo rpi-update 2>/dev/null || :
fi
