#!/usr/bin/env bash

sudo -v

sudo pacman -Syu --noconfirm && sudo topgrade -c --disable config_update --skip-notify -y
if [ -d /sys/firmware/efi ] && bootctl is-installed &>/dev/null; then
    sudo bootctl update && sudo bootctl cleanup
else
    echo "Not using systemd-boot; skipping bootctl update."
fi
if find /boot /boot/efi /mnt -name "limine.cfg" 2>/dev/null | grep -q limine; then
    echo "Limine detected"
    sudo limine-update
else
    echo "Limine not found"
fi
