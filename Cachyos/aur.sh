#!/usr/bin/env bash
# aur.sh - Chaotic AUR Setup
set -euo pipefail
IFS=$'\n\t'

# Check if already added
if grep -q "chaotic-aur" /etc/pacman.conf; then
  echo "Chaotic AUR is already configured in /etc/pacman.conf"
  exit 0
fi

echo "Adding Chaotic AUR keys..."
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB

echo "Installing keyring and mirrorlist..."
sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

echo "Configuring pacman.conf..."
# Append config if not present
printf "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n" | sudo tee -a /etc/pacman.conf >/dev/null

echo "Updating system..."
sudo pacman -Syu --noconfirm
