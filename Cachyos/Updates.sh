#!/usr/bin/env bash

set -euo pipefail

sudo -v

echo "🔄 Updating system..."
sudo pacman -Syu --noconfirm
sudo topgrade -c --disable config_update --skip-notify -y
rustup update

echo "🔍 Checking for systemd-boot..."
if [ -d /sys/firmware/efi ] && bootctl is-installed &>/dev/null; then
    echo "✅ systemd-boot is installed. Updating..."
    sudo bootctl update
    sudo bootctl cleanup
else
    echo "❌ systemd-boot not detected; skipping bootctl update."
fi

echo "🔍 Checking for Limine..."
if find /boot /boot/efi /mnt -type f -name "limine.cfg" 2>/dev/null | grep -q limine; then
    echo "✅ Limine configuration detected."

    # Check if `limine-update` is available
    if command -v limine-update &>/dev/null; then
        sudo limine-update
    else
        echo "⚠️ limine-update not found in PATH."
    fi

    # Optionally run mkinitcpio wrapper if present
    if command -v limine-mkinitcpio &>/dev/null; then
        sudo limine-mkinitcpio
    else
        echo "⚠️ limine-mkinitcpio not found in PATH."
    fi
else
    echo "❌ Limine configuration not found; skipping Limine actions."
fi
