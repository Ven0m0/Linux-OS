#!/usr/bin/env bash
# vnfetch (ven0m0-fetch), for Arch/Debian based distro's
# The goal is to keep dependencies as minimal as possible
# Credit:
# https://github.com/deathbybandaid/pimotd/blob/master/10logo
# https://github.com/juminai/dotfiles/blob/main/.local/bin/fetch
o1="$LANG"
export LC_ALL=C LANG=C
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#─────────────────────────────────────────
has() { command -v -- "$1" &>/dev/null; }
p() { printf '%s\n' "$*"; }
pe() { printf '%b\n' "$*" "$DEF"; }
#─────────────────────────────────────────
USERN="${USER:-$(id -un 2>/dev/null || echo unknown)}"
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  OS="${PRETTY_NAME:-${NAME:-unknown}}"
else
  OS="$(uname -s 2>/dev/null || echo unknown)"
fi
if ! read -r KERNEL < /proc/sys/kernel/osrelease 2>/dev/null; then
  KERNEL="$(uname -r 2>/dev/null || printf 'N/A')"
fi
if ! read -r HOSTNAME < /etc/hostname 2>/dev/null; then
  HOSTNAME="$(hostname 2>/dev/null || printf '%s' "${HOSTNAME:-unknown}")"
fi
UPT="$(uptime -p 2>/dev/null | sed 's/^up //')"
# Processes (bash: nullglob + array = safe, fast)
shopt -s nullglob
procs=(/proc/[0-9]*)
PROCS=${#procs[@]}
shopt -u nullglob

if has pacman; then
  PKG="$(pacman -Qq 2>/dev/null | wc -l)"
elif has apt; then
  PKG="$(( $(apt list --installed 2>/dev/null | wc -l) - 1 ))"
else
  PKG="N/A"
fi
PROFILE="$(powerprofilesctl get 2>/dev/null || echo N/A)"
SHELLX="${SHELL##*/}"
LOCALIP="$(ip route get 1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
GLOBALIP="$(dig +short TXT ch whoami.cloudflare @1.1.1.1 2>/dev/null | tr -d '"')"
WEATHER="$(curl -sf4 --max-time 3 --tcp-nodelay 'wttr.in/Bielefeld?format=3' 2>/dev/null | xargs)"
CPU="$(awk -F: '/^model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "N/A")"
GPU="$(lspci 2>/dev/null | awk -F: '/VGA/ {print substr($0,1,50); exit}' || echo "N/A")"
DATE="$(printf '%(%d %b %R)T\n' '-1')"
WMNAME="${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-}"
[[ -n "$DISPLAY" ]] && { pgrep -x Xorg &>/dev/null && D_SERVER="(Xorg)" || D_SERVER="(Wayland)" } || D_SERVER=""
#─────────────────────────────────────────
# Memory: totals, used, percent, GiB formatting via awk
read MemTotal MemAvailable < <(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print (t+0),(a+0)}' /proc/meminfo)
MemTotal=${MemTotal:-0}
MemAvailable=${MemAvailable:-0}
MemUsed=$((MemTotal - MemAvailable))
if [[ $MemTotal -le 0 ]]; then
  MemPct=0
else
  MemPct=$(( (MemUsed * 100 + MemTotal/2) / MemTotal ))  # rounded percent
fi
MemUsedGiB="$(awk -v m="$MemUsed" 'BEGIN{printf "%.2f", m/1048576}')"
MemTotalGiB="$(awk -v m="$MemTotal" 'BEGIN{printf "%.2f", m/1048576}')"
mem_col=$([[ $MemPct -ge 75 ]] && echo $'\e[31m' || echo $'\e[32m')
# Disk: df and findmnt (with safe defaults)
read disk_sizeKB disk_usedKB disk_availKB disk_used_pct _ < <(LC_ALL=C df -Pk / 2>/dev/null | tail -1)
read mntpoint fstype < <(findmnt -rn -o TARGET,FSTYPE / 2>/dev/null || printf '/ unknown\n')
disk_usedKB=${disk_usedKB:-0}
disk_availKB=${disk_availKB:-0}
disk_used_GiB="$(awk -v k="$disk_usedKB" 'BEGIN{printf "%.2f", k/1048576}')"
disk_avail_GiB="$(awk -v k="$disk_availKB" 'BEGIN{printf "%.2f", k/1048576}')"
disk_pct_num=${disk_used_pct%\%}
disk_pct_num=${disk_pct_num:-0}
disk_col=$([[ $disk_pct_num -ge 75 ]] && echo $'\e[31m' || echo $'\e[32m')
# Prepare colored value strings (no trailing newline)
MEMVAL="${mem_col}${MemUsedGiB} / ${MemTotalGiB} GiB (${MemPct}%)${DEF}"
DISKVAL="${disk_col}${disk_used_GiB} / ${disk_avail_GiB} GiB (${disk_pct_num}%)${DEF} - ${fstype}"
#──────────── Print output (column aligned, single write) ─────────────
labelw=14
OUT=''
append() {
  # $1 = label, $2 = value (may contain color escapes)
  printf -v _line '%-*s %s' "$labelw" "$1:" "$2"
  OUT+="${_line}"$'\n'
}
append "User"       "$USERN"
append "Host"       "$HOSTNAME"
OUT+="────────────────────"$'\n'
append "Date"       "$DATE"
append "OS"         "$OS"
append "Kernel"     "$KERNEL"
append "Uptime"     "$UPT"
append "Packages"   "$PKG"
append "Processes"  "$PROCS"
append "Shell"      "$SHELLX"
append "Terminal"   "${TERM:-N/A}"
append "WM"         "${WMNAME} ${D_SERVER}"
append "Editor"     "${EDITOR:-N/A}"
append "Memory"     "$MEMVAL"
append "Disk"       "$DISKVAL"
append "Local IP"   "${LOCALIP:-N/A}"
append "Public IP"  "${GLOBALIP:-N/A}"
append "Weather"    "${WEATHER:-N/A}"
append "Powerprofile" "$PROFILE"
append "Lang"       "${o1:-unset}"
# single print (interpret escapes)
printf '%b' "$OUT"
# ensure color reset and newline
printf '%b\n' "$DEF"
