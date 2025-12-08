#!/usr/bin/env bash
# Install BleachBit custom cleaners and link to system directories
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Colors
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m'

# Helpers
has(){ command -v "$1" &>/dev/null; }
log(){ printf '%s\n' "$*"; }
warn(){ printf '%s\n' "${YLW}WARN:${DEF} $*"; }
err(){ printf '%s\n' "${RED}ERROR:${DEF} $*" >&2; }
die(){ err "$*"; exit "${2:-1}"; }

# Package manager detection
pm_install(){
  if has paru; then
    paru --noconfirm --skipreview --needed -S "$@"
  elif has yay; then
    yay --noconfirm --needed -S "$@"
  elif has pacman; then
    sudo pacman --noconfirm --needed -S "$@"
  else
    die "No supported package manager found (paru/yay/pacman)"
  fi
}

main(){
  local src="${HOME}/.config/bleachbit/cleaners"
  local -a dsts=(/usr/share/bleachbit/cleaners /root/.config/bleachbit/cleaners)

  # Install BleachBit packages
  log "Installing BleachBit packages..."
  pm_install bleachbit bleachbit-admin cleanerml-git xorg-xhost || :

  # Verify installation
  [[ -d /usr/share/bleachbit ]] || die "/usr/share/bleachbit doesn't exist, install bleachbit first"

  # Create directories
  sudo mkdir -p /root/.config/bleachbit/cleaners
  mkdir -p "$src"

  # Link cleaners
  for dst in "${dsts[@]}"; do
    sudo install -d "$dst" || :
    for file in "$src"/*; do
      [[ -f $file ]] || continue
      sudo ln -f "$file" "$dst/${file##*/}" || :
    done
  done

  log "${GRN}Done${DEF} - BleachBit cleaners linked"
}

main "$@"
