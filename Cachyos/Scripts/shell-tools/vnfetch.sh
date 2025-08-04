#!/usr/bin/env bash

# vnfetch (ven0m0-fetch)
# For Arch/Debian based distro's
# The goal is to keep dependencies as minimal as possible
# Credit:
# https://github.com/deathbybandaid/pimotd/blob/master/10logo
# https://github.com/juminai/dotfiles/blob/main/.local/bin/fetch
# #LC_COLLATE=C LC_CTYPE=C.UTF-8 LANG=C.UTF-8
set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar inherit_errexit 2>/dev/null
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
  OS="$(uname -s)"
fi
distro="$(uname -o | awk -F '"' '/PRETTY_NAME/ { print $2 }' /etc/os-release)"
read -r KERNEL < /proc/sys/kernel/osrelease || KERNEL=$((uname -r)
read -r HOSTNAME < /etc/hostname 2>/dev/null || HOSTNAME=$(hostname)
UPT="$(uptime -p | sed 's/^up //')"
PROCS="$(ps ax | wc -l | tr -d " ")"
if command -v pacman 2>/dev/null >&2; then
  PKG_COUNT="$(pacman -Q | wc -l)"
elif command -v apt 2>/dev/null >&2; then
  PKG_COUNT="$(($(apt list --installed 2>/dev/null | wc -l) - 1))"
fi
PROFILE=$(powerprofilesctl get)
SHELLX=$(printf '%s' "${SHELL##*/}")
wmname="$XDG_CURRENT_DESKTOP $DESKTOP_SESSION"
LOCALIP=$(ip a | grep glo | awk '{print $2}' | head -1)
GLOBALIP=$(wget -q -O - http://icanhazip.com/ | tail)

CPU=$(awk -F ":" 'NR==5 {print $2}' /proc/cpuinfo | tr -s ' ')
GPU=$(lspci 2>/dev/null | awk -F ":" '/VGA/ {print $3}' | cut -c 1-50)
# check display for screensize and working environment.
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
# display server.
if [[ -n "$DISPLAY" ]]; then
    ps -e | grep -e 'wayland\|Xorg' > /dev/null && \
	D_SERVER="(Xorg)" \
	    || D_SERVER="(Wayland)"
fi
TERM_ENV=$(printf '%s' "$TERM")

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
echo $USERN
echo ──────────────
echo $OS
echo Kernel: $KERNEL
echo Uptime: $UPT
echo Packages: $PKG_COUNT
echo Processes: $PROCS
echo Shell: $SHELLX
echo $wmname
echo $wmname
echo Editor: $$EDITOR

echo ${HOSTNAME:-$(hostname)}
echo ${HOSTTYPE:-$(uname -m)}
echo $LANG $LC_ALL


