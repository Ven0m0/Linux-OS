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
#============ Safe optimal privilege tool ====================
[[ -r /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { printf '%s\n' "❌ No valid privilege escalation tool found." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v
export HOME="/home/${SUDO_USER:-$USER}"; sync
#=============================================================
sudo rm -rf --preserve-root -- /var/lib/apt/lists/*
export APT_NO_COLOR=1 NO_COLOR=1 DPKG_COLORS=never DEBIAN_FRONTEND=noninteractive
if has apt-fast; then
  "$suexec" apt-fast update -yq --allow-releaseinfo-change
  #"$suexec" apt-fast upgrade -yfq --allow-releaseinfo-change --no-install-recommends
  "$suexec" apt-fast dist-upgrade -yqf --allow-releaseinfo-change --no-install-recommends
  "$suexec" apt-fast clean -yq; "$suexec" apt-fast autoclean -yq; "$suexec" apt-fast autopurge -yq
#elif has nala; then
  "$suexec" nala upgrade -y --no-recommends
  "$suexec" nala clean; "$suexec" nala autoremove; "$suexec" nala autopurge
   #nala fetch --auto --fetches 10 --country DE
else
  "$suexec" apt-get update -yq --allow-releaseinfo-change
  "$suexec" apt-get dist-upgrade -yqfm --allow-releaseinfo-change
  "$suexec" apt-get -yqU full-upgrade --allow-releaseinfo-change
  "$suexec" apt-get clean -yq; "$suexec" apt-get autoclean -yq; "$suexec" apt-get autoremove --purge -yq
fi
# Check's the broken packages and fix them
"$suexec" dpkg --configure -a >/dev/null

"$suexec" dietpi-update 1 || "$suexec" /boot/dietpi/dietpi-update 1
has pihole && "$suexec" pihole -up
has rpi-eeprom-update && "$suexec" rpi-eeprom-update -a
has rpi-update && "$suexec" PRUNE_MODULES=1 rpi-update
#"$suexec" JUST_CHECK=1 rpi-update
# "$suexec" PRUNE_MODULES=1 rpi-update

unset LC_ALL
export LANG=C.UTF-8
