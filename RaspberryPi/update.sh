#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

sudo -v
sudo apt update -y
sudo apt upgrade -y
sudo apt dist-upgrade -y 
sudo apt full-upgrade -y

sudo /boot/dietpi/dietpi-update

if command -v pihole > /dev/null; then
    sudo pihole -up
else
    echo "Pi-hole is NOT installed"
fi

sudo rpi-eeprom-update -a
sudo JUST_CHECK=1 rpi-update
# sudo PRUNE_MODULES=1 rpi-update
