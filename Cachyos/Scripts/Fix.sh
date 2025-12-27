#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
LC_ALL=C IFS=$'\n\t'
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m' MGN=$'\e[35m' PNK=$'\e[38;5;218m' DEF=$'\e[0m' BLD=$'\e[1m'
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD
has() { command -v -- "$1" &>/dev/null; }
confirm() {
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

mirrorfix() {
  echo "Fix mirrors"
  has cachyos-rate-mirrors && sudo cachyos-rate-mirrors
  [[ -f /etc/pacman.d/chaotic-mirrorlist ]] && sudo rate-mirrors --save "/etc/pacman.d/chaotic-mirrorlist" --allow-root --disable-comments --disable-comments-in-file --entry-country DE chaotic-aur
  # rate-mirrors chaotic | sudo tee
  [[ -f /etc/pacman.d/endeavouros-mirrorlist ]] && sudo rate-mirrors --save "/etc/pacman.d/endeavouros-mirrorlist" --allow-root --disable-comments --disable-comments-in-file --entry-country DE endeavouros
}
cache() {
  sudo rm -r /var/cache/pacman/pkg/*
  has paru && paru -Scc --noconfirm || sudo pacman -Scc --noconfirm
}

echo "Fix SSH/GPG permissions"
sudo chmod -R 700 ~/.{ssh,gnupg}
echo "Fix keyrings"
sudo rm -rf /etc/pacman.d/gnupg/ /var/lib/pacman/sync
sudo pacman -Sy archlinux-keyring --noconfirm
sudo pacman-key --init --populate
sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key F3B607488DB35A47
sudo pacman-key --lsign cachyos
sudo pacman-key --refresh-keys

echo "Fix base-devel"
sudo pacman -Sy --needed base-devel --noconfirm
echo "Import wlogout GPG key"
download_file https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F /tmp/wlogout.asc && gpg --import /tmp/wlogout.asc && rm /tmp/wlogout.asc || curl -sS https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -
sudo pacman -Syyu --noconfirm
sudo mkdir -p /etc/gnupg
sudo cp ~/.local/share/omarchy/default/gpg/dirmngr.conf /etc/gnupg/
sudo chmod 644 /etc/gnupg/dirmngr.conf
sudo gpgconf --kill dirmngr || :
sudo gpgconf --launch dirmngr || :

echo "Fix Flatpak"
rm -rf ~/.local/share/flatpak/repo
mkdir -p ~/.local/share/flatpak
flatpak repair
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak update --user -y  --noninteractive
sudo flatpak update -y  --noninteractive

sudo pacman -S pam-reattach
