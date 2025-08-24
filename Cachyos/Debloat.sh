#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
sudo -v 

# Mostly useless
sudo pacman -Rns kcontacts
# sudo pacman -Rns kdeconnect
sudo pacman -Rns kpeople
# Deprecated
sudo pacman -Rncs -q cachy-browser 
sudo pacman -Rncs cachyos-v4-mirrorlist

if systemctl list-unit-files | grep -qx "pkgstats.timer"; then
  sudo systemctl stop "pkgstats.timer" &>/dev/null || :
  sudo systemctl disable "pkgstats.timer"
fi
echo '--- Remove `pkgstats` package'
if pacman -Qq pkgstats &>/dev/null; then
  sudo pacman -Rcns -q --noconfirm pkgstats &>/dev/null || :
fi

# Services
sudo systemctl disable bluetooth.service 2>/dev/null
sudo systemctl disable avahi-daemon.service 2>/dev/null
if systemctl list-unit-files | grep -q printer.service; then
    sudo systemctl disable printer.service
    echo "Printer service disabled."
else
    echo "Printer service not found. Skipping."
fi

sudo grep -xqF -- 'P2pPolicy=nothing' '/etc/fwupd/fwupd.conf' || echo 'P2pPolicy=nothing' | sudo tee -a '/etc/fwupd/fwupd.conf'

#https://wiki.archlinux.org/title/Fwupd
#P2pPolicy=nothing -> /etc/fwupd/fwupd.conf 
#passim.service
sudo ufw logging off

echo 'The script finished. Press any key to exit.'
read -n 1 -s
