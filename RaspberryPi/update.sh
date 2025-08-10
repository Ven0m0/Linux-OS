#!/usr/bin/env bash
#set -euo pipefail
#IFS=$'\n\t'
#shopt -s nullglob globstar
#export LC_ALL="C" LANG="C.UTF-8"
#WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
#cd $WORKDIR
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
#──────────── Helpers ────────────────────
# Check for command
has() { command -v "$1" &>/dev/null; }
# Print-echo
p() { printf "%s\n" "$@"; }
# Print-echo for color
pe() { printf "%b\n" "$@"; }
# Bash sleep replacement
#sleepy() { read -rt "$1" <> <(:) &>/dev/null || :; }
#─────────────────────────────────────────
#sync; sleepy 1 || sleep 1
#sudo -v
if has apt-fast; then
  apttool="apt-fast"
else
  apttool="apt-get"
fi
sudo "$apttool" update -y
sudo "$apttool" upgrade -y
sudo "$apttool" dist-upgrade -y 
#sudo apt-get update -y
#sudo apt-get upgrade -y
#sudo apt-get dist-upgrade -y 
sudo apt full-upgrade -y

# Check's the broken packages and fix them
sudo dpkg --configure -a
if [ $? -ne 0 ]; then
    p "There were issues configuring packages."
else
    p "No broken packages found or fixed successfully."
fi

if [ "$(type -t G_SUDO 2>/dev/null)" = function ]; then
    G_SUDO /boot/dietpi/dietpi-update 1
else
    sudo /boot/dietpi/dietpi-update
fi

if has pihole; then
    sudo pihole -up
else
    p "Pi-hole is NOT installed"
fi

has rpi-eeprom-update && sudo rpi-eeprom-update -a
has rpi-update && sudo JUST_CHECK=1 rpi-update
sudo JUST_CHECK=1 rpi-update
# sudo PRUNE_MODULES=1 rpi-update
