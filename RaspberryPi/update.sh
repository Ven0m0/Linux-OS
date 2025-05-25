#!/usr/bin/env bash

sudo apt-get update --allow-releaseinfo-change && sudo apt-get dist-upgrade -y && sudo apt full-upgrade -y
if command -v dietpi-launcher > /dev/null; then
    sudo dietpi-update
else
    echo "system is not dietpi"
fi
if command -v pihole > /dev/null; then
    sudo pihole -up
else
    echo "Pi-hole is NOT installed"
fi
