#!/bin/bash

sudo -v 

# Mostly useless
sudo pacman -Rns kcontacts
sudo pacman -Rns kdeconnect
sudo pacman -Rns kpeople
# Deprecated
sudo pacman -Rns cachy-browser
sudo pacman -Rns cachyos-v4-mirrorlist

# Services
systemctl disable bluetooth.service 2>/dev/null
systemctl disable avahi-daemon.service 2>/dev/null
if systemctl list-unit-files | grep -q printer.service; then
    systemctl disable printer.service
    echo "Printer service disabled."
else
    echo "Printer service not found. Skipping."
fi


echo 'The script finished. Press any key to exit.'
read -n 1 -s
