#!/bin/bash

set -euo pipefail

sudo -v

echo "🔄 Updating system..."
sudo pacman -Syu --noconfirm || true
sudo paru --cleanafter -Syu --combinedupgrade || true
sudo topgrade -c --disable config_update --skip-notify -y --no-retry --disable=uv || true
uv tool upgrade --all --compile-bytecode --native-tls || true
rustup update || true
cargo-install-update install-update --all || true
cargo-updater updater -u || true
tldr -u && sudo tldr -u || true

echo "🔍 Checking for systemd-boot..."
if [ -d /sys/firmware/efi ] && bootctl is-installed &>/dev/null; then
    echo "✅ systemd-boot is installed. Updating..."
    sudo bootctl update || true
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
