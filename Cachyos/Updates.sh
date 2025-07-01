#!/bin/bash
# shellcheck shell=bash

if command -v doas > /dev/null 2>&1; then
    suexec="doas"
elif command -v sudo-rs > /dev/null 2>&1; then
    suexec="sudo-rs"
    sudo-rs -v
else
    suexec="sudo -E"
    /usr/bin/sudo -v
fi

echo "🔄 Updating system..."
$suexec pacman -Syu --noconfirm
paru -Syu --noconfirm --combinedupgrade --nouseask -q --removemake --cleanafter --skipreview --nokeepsrc 
topgrade -c --disable=config_update --skip-notify -y --no-retry --disable=uv --disable=pipx --disable=shell || true
# pipx upgrade-all
if command -v plasma-discover-update > /dev/null 2>&1; then
    eval "$(dbus-launch)"
    plasma-discover-update
else
    echo "plasma-discover-update (Discover) is not installed."
fi
uv tool upgrade --all &
rustup update || true

if command -v cargo-updater > /dev/null 2>&1; then
    cargo-updater updater -u || true
elif command -v cargo-list > /dev/null 2>&1; then
    cargo-list list -u -a -I || true
else
    cargo-install-update install-update -a -g -j 16 || true
fi

omf update || true &
#fisher update || true ; or curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
[ -d "$HOME/.basher" ] && git -C "$HOME/.basher" pull || echo "Failed to pull from $HOME/.basher"

if [ -d ~/.basher ]; then
    echo "Updating ~/.basher..."
    git -C "$HOME/.basher" pull || echo "Failed to pull from ~/.basher"
fi

tldr -u >/dev/null 2>&1 & 
$suexec tldr -u >/dev/null 2>&1 &
$suexec sdboot-manage update > /dev/null 2>&1 && sudo sdboot-manage remove
fwupdmgr refresh  > /dev/null 2>&1 && fwupdmgr update &
$suexec updatedb &
$suexec update-desktop-database &
$suexec update-pciids > /dev/null 2>&1
$suexec update-smart-drivedb > /dev/null 2>&1

echo "🔍 Checking for systemd-boot..."
if [ -d /sys/firmware/efi ] && bootctl is-installed > /dev/null 2>&1; then
    echo "✅ systemd-boot is installed. Updating..."
    $suexec bootctl update > /dev/null 2>&1 || true
    $suexec bootctl cleanup > /dev/null 2>&1
else
    echo "❌ systemd-boot not detected; skipping bootctl update."
fi

echo "🔍 Checking for Limine..."
if fd limine.cfg /boot /boot/efi /mnt > /dev/null 2>&1; then
    echo "✅ Limine configuration detected."
    # Check if `limine-update` is available
    if command -v limine-update > /dev/null 2>&1; then
        $suexec limine-update
    else
        echo "⚠️ limine-update not found in PATH."
    fi
    # Optionally run mkinitcpio wrapper if present
    if command -v limine-mkinitcpio > /dev/null 2>&1; then
        $suexec limine-mkinitcpio
    else
        $suexec "⚠️ limine-mkinitcpio not found in PATH."
    fi
else
    $suexec "❌ Limine configuration not found; skipping Limine actions."
fi

# $suexec mkinitcpio -P
# $suexec update-initramfs -u
