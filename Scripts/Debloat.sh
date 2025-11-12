#!/usr/bin/env bash
# Unified Debloat Script for Arch-based and Debian-based systems
# Removes unnecessary packages and disables telemetry services
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
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
  echo "## Debloating Arch-based system..."
  # Remove mostly useless packages
  echo "Removing unnecessary packages..."
  sudo pacman -Rncs --noconfirm kcontacts kpeople cachy-browser cachyos-v4-mirrorlist || :
  # Remove telemetry
  echo "Removing pkgstats (telemetry)..."
  if systemctl list-unit-files | grep -qx "pkgstats.timer"; then
    sudo systemctl disable --now "pkgstats.timer" 2>/dev/null || :
  fi
  if pacman -Qq pkgstats &>/dev/null && sudo pacman -Rcns --noconfirm pkgstats &>/dev/null
  # Disable unnecessary services
  echo "Disabling unnecessary services..."
  sudo systemctl disable --now bluetooth avahi-daemon printer || :
  # Configure fwupd
  [[ -f /etc/fwupd/fwupd.conf ]] && { sudo grep -xqF -- 'P2pPolicy=nothing' '/etc/fwupd/fwupd.conf' || \
    echo 'P2pPolicy=nothing' | sudo tee -a '/etc/fwupd/fwupd.conf' >/dev/null; }
  # Disable UFW logging
  command -v ufw &>/dev/null && sudo ufw logging off 2>/dev/null || :
}

# --- Debian-based Debloat ---
debloat_debian(){
  echo "## Debloating Debian-based system..."
  # Remove LibreOffice (if not needed)
  echo "Removing LibreOffice..."
  sudo apt-get purge -y libreoffice* 2>/dev/null || :
  # Remove telemetry and reporting tools
  echo "Removing telemetry packages..."
  sudo apt-get purge -y reportbug python3-reportbug reportbug-gtk \
    apport whoopsie popularity-contest 2>/dev/null || :
  # Disable Popularity Contest
  echo "Disabling Popularity Contest..."
  [[ -f /etc/popularity-contest.conf ]] && sudo sed -i '/^PARTICIPATE=/d;$aPARTICIPATE=no' "/etc/popularity-contest.conf"
  # Disable popularity-contest cronjob
  [[ -x /etc/cron.daily/popularity-contest ]] && sudo chmod -x "/etc/cron.daily/popularity-contest"
  # Cleanup
  echo "Running apt cleanup..."
  sudo apt-get autoclean -y; sudo apt-get autoremove -y --purge
}

# --- Main Execution ---
main(){
  local platform; platform=$(detect_platform)
  echo -e "Detected platform: ${platform}\n"
  case "$platform" in
    arch) debloat_arch ;;
    debian) debloat_debian ;;
    *) echo "Error: Unsupported platform. This script supports Arch and Debian-based systems only." >&2; exit 1 ;;
  esac
  echo -e "\nDebloat complete! Press any key to exit."; read -n 1 -s
}
main "$@"
