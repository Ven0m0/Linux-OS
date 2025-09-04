#!/usr/bin/env bash
#============ Setup ====================
set -euo pipefail; shopt -s nullglob #globstar
export LC_ALL=C LANG=C DEBIAN_FRONTEND=noninteractive
WORKDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -- "$WORKDIR" || exit 1
#============ Color & Effects ============
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#============ Helpers ====================
has(){ [[ -x $(command -v -- "$1") ]]; }
hasname(){ local x; x=$(type -P -- "$1") && printf '%s\n' "${x##*/}"; }
xprintf(){ printf "%s\n" "$@"; }
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
  $LBLU  # Light Blue
  $PNK   # Pink
  $BWHT  # White
  $PNK   # Pink
  $LBLU  # Light Blue
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
#============ Sudo ====================
[[ -r /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :
suexec="$(hasname sudo-rs || hasname sudo || hasname doas || hasname run0)"
[[ -z ${suexec:-} ]] && { echo "❌ No valid privilege escalation tool found." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v 2>/dev/null || :
export HOME="/home/${SUDO_USER:-$USER}"; sync
#=============================================================
if has apt-fast; then
  "$suexec" apt-fast update -yf --allow-releaseinfo-change --allow-unauthenticated --fix-missing
  #"$suexec" apt-fast upgrade -yfq --allow-unauthenticated --fix-missing --no-install-recommends
  "$suexec" apt-fast dist-upgrade -yfq --no-install-recommends --allow-unauthenticated --fix-missing
  "$suexec" apt-fast clean -yq; "$suexec" apt-fast autoclean -yq; "$suexec" apt-fast autopurge -yq
elif has nala; then
  yes | "$suexec" nala upgrade
  "$suexec" nala clean; "$suexec" nala autoremove; "$suexec" nala autopurge
else
  "$suexec" apt-get update -y --allow-releaseinfo-change --allow-unauthenticated --fix-broken --fix-missing
  # No apt instead of apt=get for upgrade: cht.sh apt
  #"$suexec" apt upgrade -yf --allow-unauthenticated --fix-missing --no-install-recommends
  "$suexec" apt-get dist-upgrade -yf --allow-unauthenticated --fix-missing
  "$suexec" apt-get clean -yq; "$suexec" apt-get autoclean -yq; "$suexec" apt-get autoremove --purge -yq
fi
# Check's the broken packages and fix them
"$suexec" dpkg --configure -a >/dev/null
if [ $? -ne 0 ]; then
    xprintf "There were issues configuring packages."
else
    xprintf "No broken packages found or fixed successfully."
fi
"$suexec" dietpi-update 1 || "$suexec" /boot/dietpi/dietpi-update 1
has pihole && "$suexec" pihole -up || :
has rpi-eeprom-update && "$suexec" rpi-eeprom-update -a || :
has rpi-update && "$suexec" PRUNE_MODULES=1 rpi-update || :
#"$suexec" JUST_CHECK=1 rpi-update
# "$suexec" PRUNE_MODULES=1 rpi-update
