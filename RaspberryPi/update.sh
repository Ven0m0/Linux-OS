#!/usr/bin/env bash

sudo apt-get update --allow-releaseinfo-change
sudo apt-get dist-upgrade -y
sudo apt full-upgrade -y
sudo dietpi-update
if command -v pihole > /dev/null; then
    sudo pihole -up
else
    echo "Pi-hole is NOT installed"
fi
rpi-eeprom-update
