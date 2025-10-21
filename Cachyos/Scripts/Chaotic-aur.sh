#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_ALL=C

conf=/etc/pacman.conf
repo='[chaotic-aur]'
mirror='Include = /etc/pacman.d/chaotic-mirrorlist'

sudo -v
if ! grep -qF "$repo" "$conf"; then
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB
  sudo pacman -U \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  sudo sed -i "\$a\\
$repo\\
$mirror
" "$conf"
  echo "chaotic-aur added. run: sudo pacman -Syu"
else
  echo "chaotic-aur already present"
fi
