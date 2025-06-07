#!/usr/bin/bash

sudo -v

# sudo pacman -S keyserver-rank-cachy --noconfirm
sudo keyserver-rank --yes
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/mirrorlist
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/chaotic-mirrorlist
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/alhp-mirrorlist
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/cachyos-v3-mirrorlist
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/cachyos-mirrorlist
sudo cachyos-rate-mirrors
sudo pacman-db-upgrade
echo "✔ Updated mirrorlists"
