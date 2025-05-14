#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
  script_path=$([[ "$0" = /* ]] && echo "$0" || echo "$PWD/${0#./}")
  sudo "$script_path" || (
    echo 'Administrator privileges are required.'
    exit 1
  )
  exit 0
fi
export HOME="/home/${SUDO_USER:-${USER}}"

sudo pacman -Syu --noconfirm
sudo topgrade -c --disable config_update --skip-notify -y
