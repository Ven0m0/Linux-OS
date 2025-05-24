#!/usr/bin/env bash

sudo pacman -Syu --noconfirm && sudo topgrade -c --disable config_update --skip-notify -y
if bootctl is-systemd-boot | grep -q 'yes'; then
    bootctl update
else
    echo "Not using systemd-boot; skipping bootctl update."
fi
