#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
LC_ALL=C IFS=$'\n\t'
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m' MGN=$'\e[35m' PNK=$'\e[38;5;218m' DEF=$'\e[0m' BLD=$'\e[1m'
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD

has() { command -v -- "$1" &>/dev/null; }
log() { printf '%s\n' "$*"; }

download_file() {
    local url="$1"
    local output="$2"
    if has curl; then
        curl -fsSL "$url" -o "$output"
    elif has wget; then
        wget -qO "$output" "$url"
    else
        echo "Error: neither curl nor wget found" >&2
        return 1
    fi
}

confirm() {
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

fix_mirrors() {
  log "Fixing mirrors..."
  has cachyos-rate-mirrors && sudo cachyos-rate-mirrors
  if [[ -f /etc/pacman.d/chaotic-mirrorlist ]]; then
      sudo rate-mirrors --save "/etc/pacman.d/chaotic-mirrorlist" --allow-root --disable-comments --disable-comments-in-file --entry-country DE chaotic-aur || echo "Failed to update chaotic mirrors"
  fi
  if [[ -f /etc/pacman.d/endeavouros-mirrorlist ]]; then
      sudo rate-mirrors --save "/etc/pacman.d/endeavouros-mirrorlist" --allow-root --disable-comments --disable-comments-in-file --entry-country DE endeavouros || echo "Failed to update endeavouros mirrors"
  fi
}

fix_cache() {
  log "Cleaning pacman cache..."
  sudo rm -rf /var/cache/pacman/pkg/*
  if has paru; then
      paru -Scc --noconfirm
  else
      sudo pacman -Scc --noconfirm
  fi
}

fix_keys() {
  log "Fixing SSH/GPG permissions..."
  sudo chmod -R 700 ~/.{ssh,gnupg} 2>/dev/null || true
  
  log "Fixing keyrings..."
  sudo rm -rf /etc/pacman.d/gnupg/ /var/lib/pacman/sync
  sudo pacman -Sy archlinux-keyring --noconfirm
  sudo pacman-key --init --populate
  sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key F3B607488DB35A47
  
  # CachyOS keys
  sudo pacman-key --lsign cachyos || echo "Failed to lsign cachyos (maybe not present)"
  sudo pacman-key --refresh-keys || echo "Key refresh failed (network issue?)"

  log "Reinstalling base-devel..."
  sudo pacman -Sy --needed base-devel --noconfirm
  
  log "Importing wlogout GPG key..."
  if download_file "https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F" /tmp/wlogout.asc; then
      gpg --import /tmp/wlogout.asc && rm /tmp/wlogout.asc
  else
      echo "Failed to download wlogout key"
  fi
}

fix_gpg_conf() {
  log "Fixing GPG configuration..."
  sudo pacman -Syyu --noconfirm
  sudo mkdir -p /etc/gnupg
  
  # Check if source exists before copying
  if [[ -f ~/.local/share/omarchy/default/gpg/dirmngr.conf ]]; then
      sudo cp ~/.local/share/omarchy/default/gpg/dirmngr.conf /etc/gnupg/
      sudo chmod 644 /etc/gnupg/dirmngr.conf
      sudo gpgconf --kill dirmngr || :
      sudo gpgconf --launch dirmngr || :
  else
      echo "Warning: ~/.local/share/omarchy/default/gpg/dirmngr.conf not found. Skipping config copy."
  fi
}

fix_flatpak() {
  log "Fixing Flatpak..."
  rm -rf ~/.local/share/flatpak/repo
  mkdir -p ~/.local/share/flatpak
  flatpak repair
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak update --user -y --noninteractive
  sudo flatpak update -y --noninteractive
}

fix_pam() {
    log "Installing pam-reattach..."
    sudo pacman -S --needed pam-reattach --noconfirm || echo "pam-reattach install failed"
}

usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
Options:
  --mirrors     Fix mirrors
  --cache       Clean cache
  --keys        Fix keys/keyrings
  --gpg         Fix GPG config
  --flatpak     Fix Flatpak
  --pam         Fix PAM
  --all         Run all fixes
  -h, --help    Show help

Default behavior (no arguments) runs: Keys, GPG, Flatpak, and PAM fixes.
EOF
    exit 0
}

main() {
    if [[ $# -eq 0 ]]; then
        fix_keys
        fix_gpg_conf
        fix_flatpak
        fix_pam
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mirrors) fix_mirrors ;;
            --cache) fix_cache ;;
            --keys) fix_keys ;;
            --gpg) fix_gpg_conf ;;
            --flatpak) fix_flatpak ;;
            --pam) fix_pam ;;
            --all)
                fix_mirrors
                fix_cache
                fix_keys
                fix_gpg_conf
                fix_flatpak
                fix_pam
                ;;
            -h|--help) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
        shift
    done
}

main "$@"