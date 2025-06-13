#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  script_path=$([[ "$0" = /* ]] && echo "$0" || echo "$PWD/${0#./}")
  sudo "$script_path" || (
    echo 'Administrator privileges are required.'
    exit 1
  )
  exit 0
fi
export HOME="/home/${SUDO_USER:-${USER}}"


# Mostly useless
pacman -Rns kcontacts
pacman -Rns kdeconnect
pacman -Rns kpeople
pacman -Rns plasma-browser-integration
# Deprecated
pacman -Rns cachy-browser

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
