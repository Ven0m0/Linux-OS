#!/usr/bin/env bash

# vnfetch (ven0m0-fetch)
# For Arch/Debian based distro's
# The goal is to keep dependencies as minimal as possible

set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar inherit_errexit 2>/dev/null
LC_COLLATE=C LC_CTYPE=C.UTF-8 LANG=C.UTF-8
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
if [[ -f /etc/os-release ]]; then
  OS="$(awk -F= '/^NAME=/{print $2}' /etc/os-release | tr -d '"')"
else
  OS="$(uname -s)"
fi
KERNEL="$(uname -sr)"
UPT="$(uptime -p | sed 's/up//')"
PROCS="$(ps ax | wc -l | tr -d " ")"
if command -v pacman 2>/dev/null >&2; then
  PKG_COUNT="$(pacman -Q | wc -l)"
elif command -v apt 2>/dev/null >&2; then
  PKG_COUNT="$(($(apt list --installed 2>/dev/null | wc -l) - 1))"
fi
}
#─────────────────────────────────────────
echo $USER
echo ──────────────
echo Kernel: $KERNEL
echo Uptime: $UPT
echo Packages: $PKG_COUNT
echo Processes: $PROCS
echo Shell: $SHELL
echo $DESKTOP_SESSION
echo Editor: $$EDITOR
echo ${HOSTNAME:-$(hostname)}
echo ${HOSTTYPE:-$(uname -m)}
echo $LANG $LC_ALL

# https://github.com/deathbybandaid/pimotd/blob/master/10logo
Running Processes..: `ps ax | wc -l | tr -d " "`
LOCALIP=ip a | grep glo | awk '{print $2}' | head -1
GLOBALIP=wget -q -O - http://icanhazip.com/ | tail
