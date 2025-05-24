#!/usr/bin/env bash

sudo -v

sudo pacman -Syu --noconfirm && sudo topgrade -c --disable config_update --skip-notify -y
if sudo bootctl is-installed &>/dev/null; then
    sudo bootctl update && sudo bootctl cleanup
else
    echo "Not using systemd-boot; skipping bootctl update."
fi
