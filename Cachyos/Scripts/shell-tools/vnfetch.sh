#!/usr/bin/env bash
# vnfetch (ven0m0-fetch), for Arch/Debian based distros
# Heavily overoptimized bash fetch
# Credit:
# https://github.com/deathbybandaid/pimotd/blob/master/10logo
# https://github.com/juminai/dotfiles/blob/main/.local/bin/fetch
#──────────────────── Init ────────────────────
l1="$LANG" PKG= PKG2= PKG3= GLOBALIP= WEATHER=
export LC_ALL=C LANG=C
#──────────────────── Environment ────────────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#──────────────────── Basic Info ────────────────────
username="${USER:-$(id -un)}"
hostname="${HOSTNAME:-$(</etc/hostname)}"
userhost="$username@${hostname:-$(uname -n)}"
. "/etc/os-release"
OS="${NAME:-${PRETTY_NAME:-$(uname -o)}}"
KERNEL="$(</proc/sys/kernel/osrelease || uname -r)"
# Uptime
read -r rawSeconds _ </proc/uptime 
seconds=${rawSeconds%.*} uptime=""
((days=seconds/86400)) && uptime+="$days d "
((hours=seconds%86400/3600)) && uptime+="$hours h "
((minutes=seconds%3600/60)) && uptime+="$minutes m"
UPT=${uptime:-$(uptime -p)}
# Processes
shopt -s nullglob
PROCS=(/proc/[0-9]*)
PROCS=${#PROCS[@]}
shopt -u nullglob
# Packages
PKG= PKG2= PKG3=
if command -v pacman &>/dev/null; then
  mapfile -t arr < <(pacman -Qq)
  PKG="${#arr[@]} (Pacman)"
elif command -v dpkg &>/dev/null; then
  mapfile -t arr < <(dpkg --get-selections)
  PKG="${#arr[@]} (Apt)"
elif command -v apt &>/dev/null; then
  mapfile -t arr < <(apt list --installed)
  PKG="$(( ${#arr[@]} - 1 )) (Apt)"
fi
command -v cargo &>/dev/null && {
  mapfile -t arr < <(cargo install --list | grep -E '^[^[:space:]].*:')
  (( ${#arr[@]} > 0 )) && PKG2="${#arr[@]} (Cargo)"
}
command -v flatpak &>/dev/null && {
  mapfile -t arr < <(flatpak list)
  (( ${#arr[@]} > 0 )) && PKG3="${#arr[@]} (Flatpak)"
}
PACKAGE="${PKG:-} ${PKG2:-} ${PKG3:-}"
# Power plan
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
  PWPLAN="$(sort -u --parallel="$(nproc)" /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)"
elif command -v powerprofilesctl &>/dev/null; then
  PWPLAN="$(powerprofilesctl get 2>/dev/null)"
fi

SHELLX="${SHELL##*/}"
EDITORX="${EDITOR:-${VISUAL:-}}"
# Local IP
LOCALIP=$(ip -4 route get 1 | { read -r _ _ _ _ _ _ ip _; echo "${ip:-}"; })
# Public IP & Weather (backgrounded)
touch -- "${HOME}/.curl-hsts"
tmp_ip=$(mktemp)
tmp_weather=$(mktemp)
{
  if command -v dig &>/dev/null; then
    dig +short TXT ch whoami.cloudflare @1.1.1.1 | tr -d '"' > "$tmp_ip"
  else
    { curl -sfkNZ -m 3 --tcp-nodelay --tls-earlydata --tlsv1.3 --tcp-fastopen --http3 --mptcp --hsts "" ipinfo.io/ip \
      || curl -sfkNZ -m 3 --tcp-nodelay --tls-earlydata --tlsv1.3 --tcp-fastopen --http3 --mptcp --hsts "" ipecho.net/plain; } > "$tmp_ip"
  fi
} &

{ curl -sfkNZ -m 3 --tcp-nodelay --tls-earlydata --tlsv1.3 --tcp-fastopen --http3 --mptcp --hsts "" 'wttr.in/Bielefeld?format=3' > "$tmp_weather"; } &
wait
GLOBALIP=$(<"$tmp_ip")
WEATHER=$(<"$tmp_weather")
rm -f "$tmp_ip" "$tmp_weather"

# CPU/GPU
CPU="$(awk -O -F: '/^model name/ {gsub(/^[[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
if command -v nvidia-smi &>/dev/null; then
  GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
else
  GPU=$(awk -F: '/VGA|3D/ && !/Integrated/ {
      name=$3
      if(match(name, /\[(GeForce|Quadro|Titan|Radeon|RX|Vega)[^]]*\]/))
        prod=substr(name,RSTART+1,RLENGTH-2)
      else if(match(name, /(GeForce|Quadro|Titan|Radeon|RX|Vega)[^[(]*/))
        prod=substr(name,RSTART,RLENGTH)
      else
        prod=name
      gsub(/^[[ \t]+|[[ \t]+$/,"",prod)
      print prod; exit
    }' <(lspci 2>/dev/null))
fi

# Date and WM
DATE="$(printf '%(%d/%m/%y-%R)T\n' -1)"
COMPOS="${XDG_SESSION_TYPE:-${WAYLAND_DISPLAY%-*}}"
COMPOS="${COMPOS:="$(loginctl show-session $XDG_SESSION_ID -p Type --value)"}"
WMNAME="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}} ${DESKTOP_SESSION:-} ${COMPOS}"
#──────────────────── Memory ────────────────────
read -r MemTotal MemAvailable < <(awk -O '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print t+0,a+0}' /proc/meminfo)
MemTotal=${MemTotal:-0}; MemAvailable=${MemAvailable:-0}
MemUsed="$((MemTotal - MemAvailable))"
MemPct="$(( MemTotal > 0 ? (MemUsed*100 + MemTotal/2)/MemTotal : 0 ))"
MemUsedGiB="$(awk -O -v m="$MemUsed" 'BEGIN{printf "%.2f", m/1048576}')"
MemTotalGiB="$(awk -O -v m="$MemTotal" 'BEGIN{printf "%.2f", m/1048576}')"
(( MemPct >= 75 )) && mem_col="$RED" || mem_col="$GRN"
MEMVAL="${MemUsedGiB} / ${MemTotalGiB} GiB (${mem_col}${MemPct}%${DEF})"
#──────────────────── Disk ────────────────────
read -r _ _ disk_used disk_avail disk_used_pct _ < <(df -Pkh / 2>/dev/null | tail -1)
disk_pct_num=${disk_used_pct%\%}; disk_pct_num=${disk_pct_num:-0}
(( disk_pct_num>=75 )) && disk_col="$RED" || disk_col="$GRN"
fstype=$(findmnt -rn -o FSTYPE /)
DISKVAL="${disk_used:-} / ${disk_avail:-} (${disk_col}${disk_pct_num}%${DEF}) - ${fstype:-unknown}"
#──────────── Print ─────────────
labelw=14 OUT=''
append(){ [[ -n $2 && $2 != "N/A" ]] && printf -v _line '%-*s %s' "$labelw" "$1:" "$2" && OUT+="$_line"$'\n'; }

append "User"       "$userhost"
OUT+="────────────────────────────────────────────"$'\n'
append "Date"       "${DATE:-}"
append "OS"         "${OS:-}"
append "Kernel"     "${KERNEL:-}"
append "Uptime"     "$UPT"
append "Packages"   "${PACKAGE:-}"
append "Processes"  "${PROCS:-}"
append "Shell"      "${SHELLX:-}"
append "Editor"     "${EDITORX:-}"
append "Terminal"   "${TERM:-}"
append "WM"         "${WMNAME:-}"
append "Lang"       "${l1:-$LANG}"
append "CPU"        "${CPU:-}"
append "GPU"        "${GPU:-}"
append "Memory"     "$MEMVAL"
append "Disk"       "$DISKVAL"
append "Local IP"   "${LOCALIP:-}"
append "Public IP"  "${GLOBALIP:-}"
append "Weather"    "${WEATHER:-}"
append "Powerplan"  "${PWPLAN:-}"

printf '%b\n%b\n' "$OUT" "$DEF"

export LANG="C.UTF-8"; unset LC_ALL; exit
