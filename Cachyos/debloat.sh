#!/usr/bin/env bash
# Unified Debloat Script for Arch-based and Debian-based systems
# Refactored version with improved structure and maintainability
# Removes unnecessary packages and disables telemetry services
set -euo pipefail; shopt -s nullglob globstar extglob; IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="${HOME:-/home/${SUDO_USER:-$USER}}"
# Colors (trans flag palette)
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m'
export RED GRN YLW DEF
# Core helper functions
has(){ command -v -- "$1" &>/dev/null; }
xecho(){ printf '%b\n' "$*"; }
msg(){ printf '%b%s%b\n' "$GRN" "$*" "$DEF"; }
sudo -v

# --- Platform Detection ---
detect_platform(){
  if command -v pacman &>/dev/null; then
    echo "arch"
  elif command -v apt-get &>/dev/null; then
    echo "debian"
  else
    echo "unknown"
  fi
}

# --- Arch-based Debloat ---
debloat_arch(){
  msg "## Debloating Arch-based system..."
  # Remove mostly useless packages
  msg "Removing unnecessary packages..."
  sudo pacman -Rncs --noconfirm kcontacts kpeople cachy-browser cachyos-v4-mirrorlist || :
  # Remove telemetry
  msg "Removing pkgstats (telemetry)..."
  # Use systemctl is-enabled instead of list-unit-files | grep (faster)
  if systemctl is-enabled pkgstats.timer &>/dev/null; then
    sudo systemctl disable --now "pkgstats.timer" 2>/dev/null || :
  fi
  if pacman -Qq pkgstats &>/dev/null; then
    sudo pacman -Rcns --noconfirm pkgstats &>/dev/null || :
  fi
  # Disable unnecessary services
  msg "Disabling unnecessary services..."
  sudo systemctl disable --now bluetooth avahi-daemon printer NetworkManager-wait-online.service || :
  sudo systemctl mask kdump.service || :
  # Configure fwupd
  if [[ -f /etc/fwupd/fwupd.conf ]]; then
    if ! grep -xqF -- 'P2pPolicy=nothing' '/etc/fwupd/fwupd.conf'; then
      echo 'P2pPolicy=nothing' | sudo tee -a '/etc/fwupd/fwupd.conf' &>/dev/null
    fi
  fi
  has ufw && sudo ufw logging off 2>/dev/null || :
}
# --- Debian-based Debloat ---
debloat_debian(){
  msg "## Debloating Debian-based system..."
  # Remove LibreOffice (if not needed)
  msg "Removing LibreOffice..."
  sudo apt-get purge -y libreoffice* 2>/dev/null || :
  # Remove telemetry and reporting tools
  msg "Removing telemetry packages..."
  sudo apt-get purge -y reportbug python3-reportbug reportbug-gtk \
    apport whoopsie popularity-contest 2>/dev/null || :
  # Disable Popularity Contest
  msg "Disabling Popularity Contest..."
  if [[ -f /etc/popularity-contest.conf ]]; then
    if ! grep -q '^PARTICIPATE=' /etc/popularity-contest.conf; then
      printf '%s\n' 'PARTICIPATE=no' | sudo tee -a /etc/popularity-contest.conf >/dev/null
    else
      sudo sed -i 's/^PARTICIPATE=.*/PARTICIPATE=no/' /etc/popularity-contest.conf
    fi
  fi
  # Disable popularity-contest cronjob
  if [[ -x /etc/cron.daily/popularity-contest ]]; then
    sudo chmod -x "/etc/cron.daily/popularity-contest"
  fi
  # Cleanup
  msg "Running apt cleanup..."
  sudo apt-get autoclean -y
  sudo apt-get autoremove -y --purge
}
debloat_linux(){
  umask 077
}

# --- Main Execution ---
main(){
  local platform
  platform=$(detect_platform)
  msg "Detected platform: $platform"
  case "$platform" in
    arch) debloat_arch; debloat_linux ;;
    debian) debloat_debian; debloat_linux ;;
    *) debloat_linux ;;
  esac
  msg "\nDebloat complete!"
}
main "$@"
