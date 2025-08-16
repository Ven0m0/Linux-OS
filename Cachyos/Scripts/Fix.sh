#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
sudo -v

# https://github.com/ekahPruthvi/cynageOS/blob/main/Scripts/error.sh
echo -e "▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄\n██░▄▄▄██░▄▄▀██░▄▄▀██░▄▄▄░██░▄▄▀████░▄▄█░█████\n██░▄▄▄██░▀▀▄██░▀▀▄██░███░██░▀▀▄█▀▀█▄▄▀█░▄▄░██\n██░▀▀▀██░██░██░██░██░▀▀▀░██░██░█▄▄█▄▄▄█▄██▄██\n▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀\n"

# SSH fix
sudo chmod -R 700 ~/.ssh
sudo chmod -R 700 ~/.gnupg

# Other
sudo pacman -Syu --noconfirm
sudo pacman -S archlinux-keyring --noconfirm
sudo pacman-key --refresh-keys
sudo pacman-key --init
sudo pacman-key --populate
sudo pacman-key --lsign cachyos

echo "Fixing Fakeroot error"
sudo pacman -Sy --needed base-devel

echo "Fixing wlogout pgp keyring error"
curl -sS https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -

