#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
sudo -v

sudo pacman -Syy --noconfirm
sudo keyserver-rank --yes
sudo cachyos-rate-mirrors
sudo pacman-db-upgrade
echo "✔ Updated mirrorlists"
