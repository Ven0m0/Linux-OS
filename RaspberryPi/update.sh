#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# From DietPi, unsure if unsafe
# https://github.com/MichaIng/DietPi/blob/master/.build/images/dietpi-installer
# - Reset possibly conflicting environment for sub scripts
#> /etc/environment

export LC_ALL='C.UTF-8' LANG='C.UTF-8'
export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

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

if [ "$(type -t G_SUDO 2>/dev/null)" = function ]; then
    G_SUDO /boot/dietpi/dietpi-update 1
else
    sudo /boot/dietpi/dietpi-update
fi

if command -v pihole > /dev/null; then
    sudo pihole -up
else
    echo "Pi-hole is NOT installed"
fi

sudo rpi-eeprom-update -a
sudo JUST_CHECK=1 rpi-update
# sudo PRUNE_MODULES=1 rpi-update
