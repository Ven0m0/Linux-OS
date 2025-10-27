#!/usr/bin/env bash
export LC_ALL=C LANG=C; shopt -s nullglob globstar execfail
WORKDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -- "$WORKDIR" || exit 1
#============ Color & Effects ============
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#============ Helpers ====================
has(){ local x="${1:?no argument}"; local p; p=$(command -v -- "$x") || return 1; [ -x "$p" ] || return 1; }
hasname(){ local x="${1:?no argument}"; local p; p=$(type -P -- "$x" 2>/dev/null) || return 1; printf '%s\n' "${p##*/}"; }
#============ Banner ====================
banner=$(cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
)
# Split banner into array
mapfile -t banner_lines <<< "$banner"
lines=${#banner_lines[@]}
# Trans flag gradient sequence (top→bottom) using 256 colors for accuracy
flag_colors=(
  "$LBLU"   # Light Blue
  "$PNK"    # Pink
  "$BWHT"  # White
  "$PNK"    # Pink
  "$LBLU"   # Light Blue
)
segments=${#flag_colors[@]}
# If banner is trivially short, just print without dividing by (lines-1)
if (( lines <= 1 )); then
  for line in "${banner_lines[@]}"; do
    printf "%s%s%s\n" "${flag_colors[0]}" "$line" "$DEF"
  done
else
  for i in "${!banner_lines[@]}"; do
    # Map line index proportionally into 0..(segments-1)
    segment_index=$(( i * (segments - 1) / (lines - 1) ))
    (( segment_index >= segments )) && segment_index=$((segments - 1))
    printf "%s%s%s\n" "${flag_colors[segment_index]}" "${banner_lines[i]}" "$DEF"
  done
fi
echo "Meow (> ^ <)"
#============ Safety ====================
[[ -r /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null
export HOME="/home/${SUDO_USER:-$USER}"; sync
#=============================================================
sudo rm -rf --preserve-root -- /var/lib/apt/lists/*
export APT_NO_COLOR=1 NO_COLOR=1 DPKG_COLORS=never DEBIAN_FRONTEND=noninteractive
if has apt-fast; then
  sudo apt-fast update -yq --allow-releaseinfo-change
  sudo apt-fast upgrade -yfq --no-install-recommends
  sudo apt-fast dist-upgrade -yqf --no-install-recommends
  sudo apt-fast clean -yq; sudo apt-fast autoclean -yq; sudo apt-fast autopurge -yq
#elif has nala; then
  sudo nala upgrade --no-install-recommends
  sudo nala clean; sudo nala autoremove; sudo nala autopurge
   # nala fetch --auto --fetches 5 -c DE -y --non-free --debian --https-only
else
  sudo apt-get update -yfmq --allow-releaseinfo-change -o 
  sudo apt-get dist-upgrade -yqfm
  sudo apt-get -yq full-upgrade
  sudo apt-get clean -yq; sudo apt-get autoclean -yq; sudo apt-get autoremove --purge -yq
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
