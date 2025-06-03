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


echo 'The script finished. Press any key to exit.'
read -n 1 -s
