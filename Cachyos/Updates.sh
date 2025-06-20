#!/bin/bash

sudo -v

echo "🔄 Updating system..."
sudo pacman -Syu --noconfirm -q 
paru -Syu --noconfirm --combinedupgrade --nouseask -q --removemake --cleanafter --skipreview --nokeepsrc 
topgrade -c --disable config_update --skip-notify -y --no-retry --disable=uv
pipx upgrade-all
if command -v plasma-discover-update >/dev/null 2>&1; then
    export $(dbus-launch)
    plasma-discover-update
else
    echo "plasma-discover-update (Discover) is not installed."
fi
uv tool upgrade --all
export rustup="$HOME/.cargo/bin/rustup"
rustup update || true
# cargo-install-update install-update --all || true
cargo-updater updater -u
tldr -u && sudo tldr -u
sudo sdboot-manage update
sudo sdboot-manage remove
fwupdmgr refresh
fwupdmgr update
sudo updatedb 
sudo update-desktop-database 
sudo update-pciids
sudo update-smart-drivedb 

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

# sudo update-initramfs -u
