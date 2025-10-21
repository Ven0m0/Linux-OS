#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_ALL=C
declare -r CONF=/etc/pacman.conf
declare -r REPO_HEADER='[chaotic-aur]'
declare -r REPO_INCLUDE='Include = /etc/pacman.d/chaotic-mirrorlist'
declare -r KEY=3056513887B78AEB
URLS=(
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst')
has_repo(){ grep -qF "$REPO_HEADER" "$CONF"; }
recv_and_lsign(){
  sudo pacman-key --keyserver keyserver.ubuntu.com --recv-keys "$KEY"
  printf 'y\n' | sudo pacman-key --lsign-key "$KEY"
}
install_urls(){ sudo pacman --noconfirm --needed -U "${URLS[@]}"; }
append_repo(){
  sudo sed -i "\$a\\
$REPO_HEADER\\
$REPO_INCLUDE
" "$CONF"
}
if ! has_repo; then
  sudo -v
  recv_and_lsign &>/dev/null
  install_urls &>/dev/null
  append_repo
  echo "chaotic-aur added. run: sudo pacman -Syu"
  sudo pacman -Syy --noconfirm --needed >/dev/null
else
  echo "chaotic-aur already present"
fi
