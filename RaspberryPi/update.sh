#!/usr/bin/bash

sudo -v

sudo apt-get update --allow-releaseinfo-change -y -q
sudo apt-get dist-upgrade -y -q
sudo apt full-upgrade -y -q
sudo dietpi-update

if command -v pihole > /dev/null; then
    sudo pihole -up
else
    echo "Pi-hole is NOT installed"
fi


rpi-eeprom-update
# sudo PRUNE_MODULES=1 rpi-update
