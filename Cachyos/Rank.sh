#!/usr/bin/bash

sudo -v

sudo keyserver-rank --yes
sudo cachyos-rate-mirrors
sudo pacman-db-upgrade
echo "✔ Updated mirrorlists"
