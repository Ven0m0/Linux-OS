#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && sudo pacman-key --lsign-key 3056513887B78AEB && \
  sudo pacman -Uq 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' --noconfirm
echo '
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
' | sudo tee -a /etc/pacman.conf
sudo pacman -Syuq --noconfirm
