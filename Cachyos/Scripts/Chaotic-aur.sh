#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_ALL=C

conf=/etc/pacman.conf
repo='[chaotic-aur]'
mirror='Include = /etc/pacman.d/chaotic-mirrorlist'

has_repo(){ command grep -qF "$repo" "$conf"; }

if ! has_repo; then
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB
  sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
               'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  {
    echo
    echo "$repo"
    echo "$mirror"
  } | sudo tee -a "$conf" >/dev/null
  echo "chaotic-aur repo added. run: sudo pacman -Syu"
  sudo pacman -Syyu --noconfirm
else
  echo "chaotic-aur repo already present"
fi
