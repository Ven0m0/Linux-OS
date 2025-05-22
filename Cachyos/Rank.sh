#!/usr/bin/env bash
set -euo pipefail

sudo keyserver-rank --yes
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/mirrorlist
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/chaotic-mirrorlist
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/alhp-mirrorlist
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/cachyos-v3-mirrorlist
# sudo reflector -c Germany --sort rate --save /etc/pacman.d/cachyos-mirrorlist
sudo cachyos-rate-mirrors
echo "✔ Updated mirrorlists"
