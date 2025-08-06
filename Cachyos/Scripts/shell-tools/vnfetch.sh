#!/usr/bin/env bash

# vnfetch (ven0m0-fetch)
# For Arch/Debian based distro's
# The goal is to keep dependencies as minimal as possible
# Credit:
# https://github.com/deathbybandaid/pimotd/blob/master/10logo
# https://github.com/juminai/dotfiles/blob/main/.local/bin/fetch
# #LC_COLLATE=C LC_CTYPE=C.UTF-8 LANG=C.UTF-8
set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar inherit_errexit 2>/dev/null
old_LC_ALL="${LC_ALL-}" old_LANG="${LANG-}"
export LC_ALL=C LANG=C
echo Lang: $o1 LC: $o2
#──────────── Color & Effects ────────────
BLK='\e[30m' # Black
RED='\e[31m' # Red
GRN='\e[32m' # Green
YLW='\e[33m' # Yellow
BLU='\e[34m' # Blue
MGN='\e[35m' # Magenta
CYN='\e[36m' # Cyan
WHT='\e[37m' # White
DEF='\e[0m'  # Reset to default
BLD='\e[1m'  #Bold
#─────────────────────────────────────────
USERN="$(id -un)"
if [[ -f /etc/os-release ]]; then
  OS="$(awk -F= '/^NAME=/{print $2}' /etc/os-release | tr -d '"')"
else
  OS="$(uname -s)"
fi
distro="$(uname -o | awk -F '"' '/PRETTY_NAME/ { print $2 }' /etc/os-release)"
read -r KERNEL < /proc/sys/kernel/osrelease 2>/dev/null || KERNEL="$((uname -r)"
read -r HOSTNAME < /etc/hostname 2>/dev/null || HOSTNAME="$(hostname)"
ARCH="$(uname -m 2>/dev/null)"
UPT="$(uptime -p | sed 's/^up //')"
PROCS="$(ps ax | wc -l | tr -d " ")"
if command -v pacman 2>/dev/null >&2; then
  PKG="$(pacman -Q | wc -l)"
elif command -v apt 2>/dev/null >&2; then
  PKG="$(($(apt list --installed 2>/dev/null | wc -l) - 1))"
fi
PROFILE="$(powerprofilesctl get 2>/dev/null)"
SHELLX="$(printf '%s' "${SHELL##*/}")"
wmname="$XDG_CURRENT_DESKTOP $DESKTOP_SESSION"
LOCALIP=$(ip a | grep glo | awk '{print $2}' | head -1)
GLOBALIP=$(wget -q -O - http://icanhazip.com/ | tail)

CPU="$(awk -F ":" 'NR==5 {print $2}' /proc/cpuinfo | tr -s ' ')"
GPU="$(lspci 2>/dev/null | awk -F ":" '/VGA/ {print $3}' | cut -c 1-50)"

if [[ -n "$DISPLAY" ]]; then
    SCREEN=$(sed 's/,/x/' < /sys/class/graphics/fb0/virtual_size)
    [ -n "$DESKTOP_SESSION" ] && \
	WE="$DESKTOP_SESSION" \
	    || WE=$(xprop -root WM_NAME | cut -d '"' -f2)
else
    SCREEN=$(stty size | awk '{print $1 "rows " $2 "columns"}')
    tty=$(tty)
    WE=tty${tty##*/}
fi

if [[ -n "$DISPLAY" ]]; then
    ps -e | grep -e 'wayland\|Xorg' > /dev/null && \
	D_SERVER="(Xorg)" \
	    || D_SERVER="(Wayland)"
fi
TERM_ENV=$(printf '%s' "$TERM")

# ────────────────
# Memory (KiB units) — accurate: uses MemAvailable
# See: free‑memory formula using MemAvailable rather than MemFree for correct reclaimable RAM :contentReference[oaicite:2]{index=2}
read MemTotal MemAvailable < <(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {printf "%d %d\n", t, a}' /proc/meminfo)
MemUsed=$((MemTotal - MemAvailable))
MemPct=$(( (MemUsed * 100 + MemTotal/2) / MemTotal ))  # rounded percent

# Convert to Gibibytes with two decimal places
MemUsedGiB=$(awk "BEGIN {printf \"%.2f\", $MemUsed/1024/1024}")
MemTotalGiB=$(awk "BEGIN {printf \"%.2f\", $MemTotal/1024/1024}")

# ────────────────
# Disk for "/"
# POSIX df may not support --output, so use standardized parsing
# Use df -P -k to guarantee portable fields: size,used,avail,used% on mountpoint "/" (GNU & BSD support -P) :contentReference[oaicite:3]{index=3}
# Then get FSTYPE via findmnt (present on most Linuxes; safer than parsing /etc/mtab) :contentReference[oaicite:4]{index=4}
read disk_sizeKB disk_usedKB disk_availKB disk_used_pct _ < <(
  df -Pk / |
  awk 'NR==2 {print $2, $3, $4, $5, $6}'
)
fstype=$(findmnt --raw --noheadings --first-only --output FSTYPE /)

disk_used_GiB=$(awk "BEGIN {printf \"%.2f\", ${disk_usedKB}/1024/1024}")
disk_avail_GiB=$(awk "BEGIN {printf \"%.2f\", ${disk_availKB}/1024/1024}")

# ────────────────
# Color threshold: green if pct < 75 else red
[ "$MemPct" -ge 75 ] && mem_col="\033[31m" || mem_col="\033[32m"
[ "${disk_used_pct%\%}" -ge 75 ] && disk_col="\033[31m" || disk_col="\033[32m"

# Output final lines
printf 'Memory: %s / %s GiB (%s%3d%%\033[0m)\n' \
  "$MemUsedGiB" "$MemTotalGiB" "$mem_col" "$MemPct"

# note ${disk_used_pct%\%} strips trailing '%' from df output
disk_pct_num=${disk_used_pct%\%}
printf 'Disk ( / ): %s / %s GiB (%s%3d%%\033[0m) – %s\n' \
  "$disk_used_GiB" "$disk_avail_GiB" "$disk_col" "$disk_pct_num" "$fstype"

#─────────────────────────────────────────
# define space.
space() {
    printf '\n'
}
# define top decoration.
above() {
    tput smacs
    printf '\033[0;33m%s\033[0m' " " "l" 
    printf '\033[0;33mq%.0s\033[0m' $(seq 1 6)
    tput rmacs
    printf '%s\033[3;7;31m%s\033[0m' " " " ${HOSTNAME} " " "
    tput smacs
    printf '\033[0;33mq%.0s\033[0m' $(seq 1 50) 
    tput rmacs
}
# define bottom decoration.
below() {
    tput smacs
    printf '\033[0;33m%s\033[0m' " " "m"
    printf '\033[0;33mq%.0s\033[0m' $(seq 1 50)
    tput rmacs
}
space
above
# print formated information.
printf "
  \033[1;37m OS: \033[30m ..................\033[0m \033[3;37m  ${OS} \033[0m
  \033[1;37m Kernel: \033[30m ..............\033[0m \033[3;37m  ${KERNEL}-${ARCH} \033[0m
  \033[1;37m Init: \033[30m ................\033[0m \033[3;37m  ${INIT} \033[0m
  \033[1;37m Processor: \033[30m ...........\033[0m \033[3;37m ${CPU} \033[0m
  \033[1;37m Graphics:\033[30m .............\033[0m \033[3;37m ${GPU} \033[0m
  \033[1;37m Mem: \033[30m .................\033[0m \033[3;37m  ${RAM}Mib ${SWAP}Mib\033[0m
  \033[1;37m Packages: \033[30m ............\033[0m \033[3;37m  ${PKG} \033[0m
  \033[1;37m Workplace: \033[30m ...........\033[0m \033[3;37m  ${WE} ${D_SERVER} ${SCREEN}\033[0m
  \033[1;37m Term Env: \033[30m ............\033[0m \033[3;37m  ${TERM_ENV} \033[0m
  \033[1;37m Shell: \033[30m ...............\033[0m \033[3;37m  ${SHELL} \033[0m
"
below
space 

#─────────────────────────────────────────
echo ${USERN}─${HOSTNAME}
echo ────────────────────
echo $OS
echo Kernel: $KERNEL
echo Uptime: $UPT
echo Packages: $PKG
echo Processes: $PROCS
echo Shell: $SHELLX
echo $wmname $D_SERVER
echo Editor: $$EDITOR
echo Powerprofile: $PROFILE
echo "Lang: ${o2:-unset}, LC_ALL: ${o1:-unset}"
