#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
sudo -v

# Determine the device mounted at root
ROOT_DEV=$(findmnt -n -o SOURCE /)

# Check the filesystem type of the root device
FSTYPE=$(findmnt -n -o FSTYPE /)

# If the filesystem is ext4, execute the tune2fs command
if [[ "$FSTYPE" == "ext4" ]]; then
    echo "Root filesystem is ext4 on $ROOT_DEV"
    sudo tune2fs -O fast_commit "$ROOT_DEV"
else
    echo "Root filesystem is not ext4 (detected: $FSTYPE). Skipping tune2fs."
fi

sudo balooctl6 disable && sudo balooctl6 purge

echo "Applying Breeze Dark theme"
kwriteconfig6 --file ~/.config/kdeglobals --group General --key ColorScheme "BreezeDark"
plasma-apply-desktoptheme breeze-dark

sed -i 's/opacity = 0.8/opacity = 1.0/' "$HOME/.config/alacritty/alacritty.toml"

sudo curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Linux-Settings/etc/sysctl.d/99-tweak-settings.conf -o /etc/sysctl.d/99-tweak-settings.conf


echo "Debloat and fixup"
sudo pacman -Rns cachyos-v4-mirrorlist --noconfirm || true
sudo pacman -Rns cachy-browser --noconfirm || true


echo "install basher from https://github.com/basherpm/basher"
curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash
