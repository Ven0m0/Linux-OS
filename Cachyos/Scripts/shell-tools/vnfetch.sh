#!/usr/bin/env bash
# vnfetch (ven0m0-fetch), for Arch/Debian based distros
# Heavily overoptimized bash fetch
# Credit:
# https://github.com/deathbybandaid/pimotd/blob/master/10logo
# https://github.com/juminai/dotfiles/blob/main/.local/bin/fetch

#──────────────────── Init ────────────────────
l1="$LANG" PKG= PKG2= PKG3= GLOBALIP= WEATHER=

#──────────────────── Environment ────────────────────
export LC_ALL=C LANG=C
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'

#──────────────────── Basic Info ────────────────────
. "/etc/os-release"
OS="${NAME:-${PRETTY_NAME:-$(uname -o)}}"
KERNEL="$(</proc/sys/kernel/osrelease || uname -r)"
UPT="$(uptime -p)"; UPT="${UPT#up }"

# Processes
shopt -s nullglob
files=(/proc/[0-9]*)
PROCS=${#files[@]}
shopt -u nullglob

# Packages
if command -v pacman &>/dev/null; then
  PKG="$(pacman -Qq | wc -l)"; PKG="${PKG} (Pacman)"
elif command -v dpkg &>/dev/null; then
  PKG="$(dpkg --get-selections | wc -l)"; PKG="${PKG} (Apt)"
elif command -v apt &>/dev/null; then
  PKG="$(( $(apt list --installed | wc -l) - 1 ))"; PKG="${PKG} (Apt)"
fi

command -v cargo &>/dev/null && {
  PKG2=$(cargo install --list | grep -c '^[^[:space:]].*:')
  [[ ${PKG2:-0} -gt 0 ]] && PKG2="${PKG2} (Cargo)"
}

command -v flatpak &>/dev/null && {
  PKG3=$(flatpak list | wc -l)
  [[ ${PKG3:-0} -gt 0 ]] && PKG3="${PKG3} (Flatpak)"
}

PACKAGE="${PKG:-} ${PKG2:-} ${PKG3:-}"

# Power plan
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
  PWPLAN="$(sort -u --parallel=16 /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)"
else
  if command -v powerprofilesctl &>/dev/null; then
    PWPLAN="$(powerprofilesctl get 2>/dev/null)"
  fi
fi

SHELLX="${SHELL##*/}"
EDITORX="${EDITOR:-${VISUAL:-}}"

# Local IP
LOCALIP=$(ip -4 route get 1 | { read -r _ _ _ _ _ _ ip _; echo "${ip:-}"; })

# Curl setup
touch -- "${HOME}/.curl-hsts"

# Public IP
if command -v dig &>/dev/null; then
  IFS= read -r GLOBALIP < <(dig +short TXT ch whoami.cloudflare @1.1.1.1)
  GLOBALIP="${GLOBALIP//\"/}"
else
  IFS= read -r GLOBALIP < <(curl -sf4 --max-time 3 --tcp-nodelay --hsts "${HOME}/.curl-hsts" ipinfo.io/ip || \
                            curl -sf4 --max-time 3 --tcp-nodelay --hsts "${HOME}/.curl-hsts" ipecho.net/plain)
fi

# Weather
IFS= read -r WEATHER < <(curl -sf4 --max-time 3 --tcp-nodelay --hsts "${HOME}/.curl-hsts" 'wttr.in/Bielefeld?format=3')

# CPU/GPU
CPU="$(awk -O -F: '/^model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
GPU=$(
  if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name --format=csv,noheader | head -n1
  else
    lspci 2>/dev/null | awk -O -F: '/VGA|3D/ && !/Integrated/ {
      name = $3
      if (match(name, /\[(GeForce|Quadro|Titan|Radeon|RX|Vega)[^]]*\]/)) {
        prod = substr(name, RSTART+1, RLENGTH-2)
      } else if (match(name, /(GeForce|Quadro|Titan|Radeon|RX|Vega)[^[(]*/)) {
        prod = substr(name, RSTART, RLENGTH)
      } else {
        prod = name
      }
      gsub(/^[ \t]+|[ \t]+$/, "", prod)
      print prod
      exit
    }'
  fi
)

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
append(){ [[ -n $2 && $2 != "N/A" ]] && printf -v _line '%-*s %s' "$labelw" "$1:" "$2" && OUT+="${_line}"$'\n'; }

append "User"       "${USER}@${HOSTNAME}"
OUT+="────────────────────────────────────────────"$'\n'
append "Date"       "${DATE:-}"
append "OS"         "${OS:-}"
append "Kernel"     "${KERNEL:-}"
append "Uptime"     "${UPT:-}"
append "Packages"   "${PACKAGE:-}"
append "Processes"  "${PROCS:-}"
append "Shell"      "${SHELLX:-}"
append "Editor"     "${EDITORX:-}"
append "Terminal"   "${TERM:-}"
append "WM"         "${WMNAME:-}"
append "Lang"       "${l1:-}"
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
