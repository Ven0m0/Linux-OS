#!/usr/bin/env bash
# vnfetch (ven0m0-fetch), for Arch/Debian based distro's
# The goal is to keep dependencies as minimal as possible
# Credit:
# https://github.com/deathbybandaid/pimotd/blob/master/10logo
# https://github.com/juminai/dotfiles/blob/main/.local/bin/fetch
o1="$$LANG"
export LC_ALL=C LANG=C
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
  OS="$(uname -s 2>/dev/null)"
fi
distro="$(awk -F '"' '/PRETTY_NAME/ { print $2 }' /etc/os-release)"
read -r KERNEL < /proc/sys/kernel/osrelease 2>/dev/null || KERNEL="$(uname -r 2>/dev/null)"
read -r HOSTNAME < /etc/hostname 2>/dev/null || HOSTNAME="${HOSTNAME:-$(hostname 2>/dev/null)}"
#ARCH="$(uname -m 2>/dev/null)"
UPT="$(uptime -p 2>/dev/null | sed 's/^up //')"
PROCS="$(ps ax 2>/dev/null | wc -l | tr -d " ")"
if command -v pacman &>/dev/null; then
  PKG="$(pacman -Q 2>/dev/null | wc -l)"
elif command -v apt &>/dev/null; then
  PKG="$(($(apt list --installed 2>/dev/null | wc -l) - 1))"
fi
PROFILE="$(powerprofilesctl get 2>/dev/null)"
SHELLX="$(printf '%s' "${SHELL##*/}")"
LOCALIP="$(\ip route get 1 | tr -s ' ' | cut -d' ' -f7)"
public_ip="$(dig +time=1 +tries=1 +short TXT ch whoami.cloudflare @1.1.1.1 | tr -d '"')"
#GLOBALIP="$(\curl -s4 icanhazip.com 2>/dev/null)"
weather="$(\curl -s4 "wttr.in/Bielefeld?format=3" 2>/dev/null)"
CPU="$(LC_ALL=C awk -F ":" 'NR==5 {print $2}' /proc/cpuinfo 2>/dev/null | tr -s ' ')"
GPU="$(LC_ALL=C lspci 2>/dev/null | awk -F ":" '/VGA/ {print $3}' | cut -c 1-50)"
DATE="$(printf '%(%d %b %R)T\n' '-1')"

wmname="${XDG_CURRENT_DESKTOP} ${DESKTOP_SESSION}"
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
mntpoint="$(findmnt -rnf -o TARGET 2>/dev/null)"
fstype="$(findmnt -rnf -o FSTYPE "${mntpoint:-/}" 2>/dev/null)"
disk_used_GiB=$(awk "BEGIN {printf \"%.2f\", ${disk_usedKB}/1024/1024}")
disk_avail_GiB=$(awk "BEGIN {printf \"%.2f\", ${disk_availKB}/1024/1024}")
# ────────────────
# Color threshold: green if pct < 75 else red
[[ "$MemPct" -ge 75 ]] && mem_col=$'\e[31m' || mem_col=$'\e[32m'
[[ "${disk_used_pct%\%}" -ge 75 ]] && disk_col=$'\e[31m' || disk_col=$'\e[32m'
MEM="$(printf 'Memory: %s / %s GiB (%s%d%%\e[0m)\n' "$MemUsedGiB" "$MemTotalGiB" "$mem_col" "$MemPct")"

# note ${disk_used_pct%\%} strips trailing '%' from df output
disk_pct_num=${disk_used_pct%\%}
DISK="$(printf "Disk (${mntpoint:-/}): %s / %s GiB (%s%d%%\e[0m) – %s\n" "$disk_used_GiB" "$disk_avail_GiB" "$disk_col" "$disk_pct_num" "$fstype")"
#─────────────────────────────────────────
echo ${USERN}─${HOSTNAME}
echo ────────────────────
echo ${DATE}
echo ${OS}
echo Kernel: $KERNEL
echo Uptime: $UPT
echo Packages: $PKG
echo Processes: $PROCS
echo Shell: $SHELLX
echo WM: ${wmname} ${D_SERVER}
echo Editor: ${EDITOR}
echo ${MEM}
echo ${DISK}
echo ${LOCALIP}
echo${public_ip}
echo Powerprofile: $PROFILE
echo "Lang: ${o1:-unset}
