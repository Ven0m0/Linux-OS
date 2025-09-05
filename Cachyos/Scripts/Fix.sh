#!/usr/bin/env bash
set -euo pipefail; LC_ALL=C LANG=C.UTF-8

# https://github.com/ekahPruthvi/cynageOS/blob/main/Scripts/error.sh
echo -e "▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄\n██░▄▄▄██░▄▄▀██░▄▄▀██░▄▄▄░██░▄▄▀████░▄▄█░█████\n██░▄▄▄██░▀▀▄██░▀▀▄██░███░██░▀▀▄█▀▀█▄▄▀█░▄▄░██\n██░▀▀▀██░██░██░██░██░▀▀▀░██░██░█▄▄█▄▄▄█▄██▄██\n▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀\n"

sudo -v

# https://wiki.cachyos.org/cachyos_basic/faq/
echo "Fix mirrors"
command -v cachyos-rate-mirrors &>/dev/null && sudo cachyos-rate-mirrors
sudo rm -r /var/cache/pacman/pkg/*

# SSH fix
sudo chmod -R 744 ~/.ssh
sudo chmod -R 744 ~/.gnupg

# Fix keyrings
sudo rm -rf /etc/pacman.d/gnupg/ # Force-remove the old keyrings
sudo pacman -Sy archlinux-keyring --noconfirm || sudo pacman -Sy archlinux-keyring --noconfirm
sudo pacman-key --refresh-keys
sudo pacman-key --init # Initialize the keyring
sudo pacman-key --populate # Populate the keyring
sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com # Manually import the CachyOS key
sudo pacman-key --lsign-key F3B607488DB35A47 # Manually sign the key
sudo pacman-key --lsign cachyos
sudo rm -R /var/lib/pacman/sync # Remove the synced databases to force a fresh download

echo "Fixing Fakeroot error"
sudo pacman -Sy --needed base-devel

echo "Fixing wlogout pgp keyring error"
curl -sS https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -

sudo pacman -Syy --noconfirm
