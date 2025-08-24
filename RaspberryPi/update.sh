#!/usr/bin/env bash
#──────────── Setup ────────────────────
shopt -s nullglob globstar
export LC_ALL=C LANG=C
WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd $WORKDIR
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#──────────── Helpers ────────────────────
has(){ command -v -- "$1" &>/dev/null; }
hasname(){
  local x
  if ! x=$(type -P -- "$1"); then
    return 1
  fi
  printf '%s\n' "${x##*/}"
}
xprintf(){ printf "%s\n" "$@"; }
#──────────── Banner ────────────────────
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
#──────────── Sudo ────────────────────
[[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v 2>/dev/null || :
export HOME="/home/${SUDO_USER:-$USER}"; sync
#─────────────────────────────────────────────────────────────
if has nala; then
  "$suexec" nala fetch --auto --sources --fetches 5 --non-free -y -c DE
  "$suexec" nala upgrade
  "$suexec" nala autoremove && "$suexec" nala autopurge
elif has apt-fast; then
  "$suexec" apt-fast update -y && "$suexec" apt-fast upgrade -y
  "$suexec" apt-fast dist-upgrade -y && "$suexec" apt-fast full-upgrade -y
  "$suexec" apt-fast autoremove
else
  "$suexec" apt-get update -y --allow-releaseinfo-change && "$suexec" apt-get upgrade -y
  "$suexec" apt-get dist-upgrade -y && "$suexec" apt full-upgrade -y
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
