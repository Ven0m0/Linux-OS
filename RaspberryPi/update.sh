#!/usr/bin/bash

sudo -v

sudo apt update -y
sudo apt upgrade -y
sudo apt dist-upgrade -y 
sudo apt full-upgrade -y
sudo dietpi-update

if command -v pihole > /dev/null; then
    sudo pihole -up
else
    echo "Pi-hole is NOT installed"
fi


rpi-eeprom-update
# sudo PRUNE_MODULES=1 rpi-update
