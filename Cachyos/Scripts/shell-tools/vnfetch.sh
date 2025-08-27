#!/usr/bin/env bash
# shopt -s nullglob globstar &>/dev/null
# IFS=$'\n\t'
# vnfetch (ven0m0-fetch), for Arch/Debian based distro's
# The goal is to keep dependencies as minimal as possible
# Credit:
# https://github.com/deathbybandaid/pimotd/blob/master/10logo
# https://github.com/juminai/dotfiles/blob/main/.local/bin/fetch
l1="$LANG"
export LC_ALL=C LANG=C
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#─────────────────────────────────────────
#xecho(){ printf '%s\n' "$*"; }
#xeecho(){ printf '%b\n' "$*" "$DEF"; }
#─────────────────────────────────────────
USERN="${USER:-$(LC_ALL=C id -un 2>/dev/null || echo unknown)}"
#if [[ -r /etc/os-release ]]; then
  #. /etc/os-release 2>/dev/null
  #OS="${NAME:-${PRETTY_NAME:-unknown}}"
#else
  #OS="$(LC_ALL=C uname -o 2>/dev/null || echo unknown)"
#fi
if . /etc/os-release &>/dev/null; then
  OS="${NAME:-${PRETTY_NAME:-unknown}}"
else
  OS="$(LC_ALL=C uname -o 2>/dev/null || echo unknown)"
fi
if ! read -r KERNEL < /proc/sys/kernel/osrelease 2>/dev/null; then
  KERNEL="$(LC_ALL=C uname -r 2>/dev/null || printf 'N/A')"
fi
if ! read -r HOSTNAME < /etc/hostname 2>/dev/null; then
  HOSTNAME="$(LC_ALL=C hostname 2>/dev/null || printf '%s' "${HOSTNAME:-unknown}")"
fi
UPT="$(LC_ALL=C uptime -p 2>/dev/null | LC_ALL=C sed 's/^up //')"
# Processes (bash: nullglob + array = safe, fast)
shopt -s nullglob &>/dev/null
procs=(/proc/[0-9]*)
PROCS=${#procs[@]}
shopt -u nullglob &>/dev/null
if command -v pacman &>/dev/null; then
  PKG="$(LC_ALL=C pacman -Qq 2>/dev/null | LC_ALL=C wc -l)"
elif command -v apt-fast &>/dev/null; then
  PKG="$(( $(LC_ALL=C apt-fast list --installed 2>/dev/null | LC_ALL=C wc -l) - 1 ))"
elif command -v apt &>/dev/null; then
  PKG="$(( $(LC_ALL=C apt list --installed 2>/dev/null | LC_ALL=C wc -l) - 1 ))"
else
  PKG="N/A"
fi
if command -v cargo &>/dev/null; then
  PKG2="$(LC_ALL=C cargo install --list | LC_ALL=C grep -c '^[^[:space:]].*:')"
PWPLAN="$(LC_ALL=C powerprofilesctl get 2>/dev/null || echo N/A)"
SHELLX="${SHELL##*/}"
LOCALIP=$(LC_ALL=C ip -4 route get 1 2>/dev/null | { read -r _ _ _ _ _ _ ip _; echo "$ip"; })
#LOCALIP="$(LC_ALL=C ip route get 1 2>/dev/null | LC_ALL=C sed -n 's/.*src \([0-9.]*\).*/\1/p')"
if command -v dig &>/dev/null; then
  GLOBALIP="$(LC_ALL=C dig +short TXT ch whoami.cloudflare @1.1.1.1 2>/dev/null | tr -d '"')"
else
  GLOBALIP="$(LC_ALL=C curl -sf4 --max-time 3 --tcp-nodelay ipinfo.io/ip 2>/dev/null || LC_ALL=C curl -sf4 --max-time 3 --tcp-nodelay ipecho.net/plain 2>/dev/null)"
fi
WEATHER="$(curl -sf4 --max-time 3 --tcp-nodelay 'wttr.in/Bielefeld?format=3' 2>/dev/null | xargs)"
CPU="$(LC_ALL=C awk -F: '/^model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "N/A")"
GPU="$(LC_ALL=C lspci 2>/dev/null | LC_ALL=C awk -F: '/VGA/ {print substr($0,1,50); exit}' || echo "N/A")"
DATE="$(printf '%(%d %b %R)T\n' '-1')"
WMNAME="${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-}"
[[ -n "$DISPLAY" ]] && { LC_ALL=C pgrep -x Xorg &>/dev/null && D_SERVER="(Xorg)" || D_SERVER="(Wayland)"; } || D_SERVER=""
#─────────────────────────────────────────
# Memory: totals, used, percent, GiB formatting via awk
read -r MemTotal MemAvailable < <(LC_ALL=C awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print (t+0),(a+0)}' /proc/meminfo)
MemTotal=${MemTotal:-0}
MemAvailable=${MemAvailable:-0}
MemUsed=$((MemTotal - MemAvailable))
if [[ $MemTotal -le 0 ]]; then
  MemPct=0
else
  MemPct=$(( (MemUsed * 100 + MemTotal/2) / MemTotal ))  # rounded percent
fi
MemUsedGiB="$(LC_ALL=C awk -v m="$MemUsed" 'BEGIN{printf "%.2f", m/1048576}')"
MemTotalGiB="$(LC_ALL=C awk -v m="$MemTotal" 'BEGIN{printf "%.2f", m/1048576}')"
mem_col=$([[ $MemPct -ge 75 ]] && echo $'\e[31m' || echo $'\e[32m')
# Prepare colored value strings (no trailing newline)
MEMVAL="${MemUsedGiB} / ${MemTotalGiB} GiB (${mem_col}${MemPct}%${DEF})"
# Disk: human-readable sizes
read -r _ _ disk_used disk_avail disk_used_pct _ < <(LC_ALL=C df -Pkh / 2>/dev/null | LC_ALL=C tail -1)
read -r fstype < <(LC_ALL=C findmnt -rn -o FSTYPE / 2>/dev/null || printf 'unknown\n')
disk_used=${disk_used:-N/A}
disk_avail=${disk_avail:-N/A}
disk_pct_num=${disk_used_pct%\%}
disk_pct_num=${disk_pct_num:-0}
disk_col=$([[ $disk_pct_num -ge 75 ]] && echo $'\e[31m' || echo $'\e[32m')
# Only color the percentage
DISKVAL="${disk_used} / ${disk_avail} (${disk_col}${disk_pct_num}%${DEF}) - ${fstype:-unknown}"
#──────────── Print output (column aligned, single write) ─────────────
labelw=14
OUT=''
append() {
  # $1 = label, $2 = value (may contain color escapes)
  printf -v _line '%-*s %s' "$labelw" "$1:" "$2"
  OUT+="$_line"$'\n'
}
append "User"       "$USERN"@"$HOSTNAME"
OUT+="────────────────────────────────────────────"$'\n'
append "Date"       "$DATE"
append "OS"         "$OS"
append "Kernel"     "$KERNEL"
append "Uptime"     "$UPT"
append "Packages"   "$PKG"
append "Processes"  "$PROCS"
append "Shell"      "$SHELLX"
append "Editor"     "${EDITOR:-VISUAL:-N/A}"
append "Terminal"   "${TERM:-N/A}"
append "WM"         "${WMNAME} ${D_SERVER}"
append "Lang"       "${l1:-unset}"
append "Memory"     "$MEMVAL"
append "Disk"       "$DISKVAL"
append "Local IP"   "${LOCALIP:-N/A}"
append "Public IP"  "${GLOBALIP:-N/A}"
append "Weather"    "${WEATHER:-N/A}"
append "Powerplan"  "${PWPLAN:-N/A}"
# single print (interpret escapes)
printf '%b' "$OUT"
# ensure color reset and newline
printf '%b\n' "$DEF"
