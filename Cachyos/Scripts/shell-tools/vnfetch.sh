#!/usr/bin/env bash
# shopt -s nullglob globstar &>/dev/null
# IFS=$'\n\t'
# vnfetch (ven0m0-fetch), for Arch/Debian based distro's
# The goal is to keep dependencies as minimal as possible
# Credit:
# https://github.com/deathbybandaid/pimotd/blob/master/10logo
# https://github.com/juminai/dotfiles/blob/main/.local/bin/fetch
#──────────────────── Environment ────────────────────
l1="$LANG"; export LC_ALL=C LANG=C
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#──────────────────── Basic Info ────────────────────
. /etc/os-release &>/dev/null && OS="${NAME:-$PRETTY_NAME}" || OS="$(uname -o 2>/dev/null)"
KERNEL="$(</proc/sys/kernel/osrelease 2>/dev/null || uname -r 2>/dev/null)"
#USERN="${USER:-$(LC_ALL=C id -un 2>/dev/null || echo unknown)}"
#HOSTNAME=$(</etc/hostname 2>/dev/null || hostname 2>/dev/null || echo "unknown")
UPT="$(uptime -p 2>/dev/null)"; UPT="${UPT#up }"
# Processes
shopt -s nullglob &>/dev/null
procs="(/proc/[0-9]*)"; PROCS="${#procs[@]}"
shopt -u nullglob &>/dev/null
# Packages
if command -v pacman &>/dev/null; then
  PKG="$(pacman -Qq 2>/dev/null | wc -l) (Pacman)"
elif command -v apt-fast &>/dev/null; then
  PKG="$(( $(apt-fast list --installed 2>/dev/null | wc -l) - 1 )) (Apt)"
elif command -v apt &>/dev/null; then
  PKG="$(( $(apt list --installed 2>/dev/null | wc -l) - 1 )) (Apt)"
fi
PKG2="$(command -v cargo &>/dev/null && cargo install --list 2>/dev/null | grep -c '^[^[:space:]].*:') (Cargo)"
PACKAGE="${PKG:-} ${PKG2:-}"
PWPLAN="$(powerprofilesctl get 2>/dev/null)"
SHELLX="${SHELL##*/}"
# Local IP
LOCALIP=$(LC_ALL=C ip -4 route get 1 2>/dev/null | { read -r _ _ _ _ _ _ ip _; echo "$ip"; })
#LOCALIP="$(LC_ALL=C ip route get 1 2>/dev/null | LC_ALL=C sed -n 's/.*src \([0-9.]*\).*/\1/p')"
# Public IP
if command -v dig &>/dev/null; then
  GLOBALIP="$(dig +short TXT ch whoami.cloudflare @1.1.1.1 2>/dev/null | tr -d '"')"
else
  GLOBALIP="$(curl -sf4 --max-time 3 --tcp-nodelay ipinfo.io/ip 2>/dev/null || curl -sf4 --max-time 3 --tcp-nodelay ipecho.net/plain 2>/dev/null)"
fi
# Weather
WEATHER="$(curl -sf4 --max-time 3 --tcp-nodelay 'wttr.in/Bielefeld?format=3' 2>/dev/null | xargs)"
# CPU/GPU
CPU="$(awk -F: '/^model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "N/A")"
GPU="$(lspci 2>/dev/null | awk -F: '/VGA/ {print substr($0,1,50); exit}' || echo "N/A")"
# Date and WM
DATE="$(printf '%(%d %b %R)T\n' '-1')"
WMNAME="${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-}"
[[ -n "$DISPLAY" ]] && { pgrep -x wayland && D_SERVER="(Wayland)" } || { pgrep -x xorg && D_SERVER="(X11)"; }
#──────────────────── Memory ────────────────────
read -r MemTotal MemAvailable < <(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print t+0,a+0}' /proc/meminfo)
MemTotal=${MemTotal:-0}; MemAvailable=${MemAvailable:-0}
MemUsed="$((MemTotal - MemAvailable))"
MemPct="$(( MemTotal > 0 ? (MemUsed*100 + MemTotal/2)/MemTotal : 0 ))"
MemUsedGiB="$(awk -v m="$MemUsed" 'BEGIN{printf "%.2f", m/1048576}')"
MemTotalGiB="$(awk -v m="$MemTotal" 'BEGIN{printf "%.2f", m/1048576}')"
(( MemPct >= 75 )) && mem_col=$'\e[31m' || mem_col=$'\e[32m'
MEMVAL="${MemUsedGiB} / ${MemTotalGiB} GiB (${mem_col}${MemPct}%${DEF})"
#──────────────────── Disk ────────────────────
read -r _ _ disk_used disk_avail disk_used_pct _ < <(df -Pkh / 2>/dev/null | tail -1)
disk_pct_num=${disk_used_pct%\%}; disk_pct_num=${disk_pct_num:-0}
(( disk_pct_num >= 75 )) && disk_col=$'\e[31m' || disk_col=$'\e[32m'
fstype=$(findmnt -rn -o FSTYPE / 2>/dev/null)
DISKVAL="${disk_used:-N/A} / ${disk_avail:-N/A} (${disk_col}${disk_pct_num}%${DEF}) - ${fstype:-unknown}"
#──────────── Print ─────────────
labelw=14; OUT=''
append(){ printf -v _line '%-*s %s' "$labelw" "$1:" "$2"; OUT+="$_line"$'\n'; }
#──────────── Layout ─────────────
append "User"       "$USER"@"$HOSTNAME"
OUT+="────────────────────────────────────────────"$'\n'
append "Date"       "$DATE"
append "OS"         "${OS:-N/A}"
append "Kernel"     "${KERNEL:-N/A}"
append "Uptime"     "${UPT:-N/A}"
append "Packages"   "${PACKAGE:-N/A}"
append "Processes"  "$PROCS"
append "Shell"      "$SHELLX"
append "Editor"     "${EDITOR:-VISUAL:-N/A}"
append "Terminal"   "${TERM:-N/A}"
append "WM"         "${WMNAME:-} ${D_SERVER:-}"
append "Lang"       "${l1:-unset}"
append "Memory"     "$MEMVAL"
append "Disk"       "$DISKVAL"
append "Local IP"   "${LOCALIP:-N/A}"
append "Public IP"  "${GLOBALIP:-N/A}"
append "Weather"    "${WEATHER:-N/A}"
append "Powerplan"  "${PWPLAN:-N/A}"
printf '%b\n%b\n' "$OUT" "$DEF"
