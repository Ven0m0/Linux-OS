#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

sudo -v
sudo apt update -y
sudo apt upgrade -y
sudo apt dist-upgrade -y 
sudo apt full-upgrade -y

# Check's the broken packages and fix them
sudo dpkg --configure -a
if [ $? -ne 0 ]; then
    error_message "There were issues configuring packages."
else
    success_message "No broken packages found or fixed successfully."
fi

sudo /boot/dietpi/dietpi-update

if command -v pihole > /dev/null; then
    sudo pihole -up
else
    echo "Pi-hole is NOT installed"
fi

sudo rpi-eeprom-update -a
sudo JUST_CHECK=1 rpi-update
# sudo PRUNE_MODULES=1 rpi-update
