#!/usr/bin/env bash
# Unified Debloat Script for Arch-based and Debian-based systems
# Removes unnecessary packages and disables telemetry services

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
export HOME="/home/${SUDO_USER:-$USER}"

# Ensure sudo access
sudo -v

# --- Platform Detection ---
detect_platform() {
  if command -v pacman &>/dev/null; then
    echo "arch"
  elif command -v apt-get &>/dev/null; then
    echo "debian"
  else
    echo "unknown"
  fi
}

# --- Arch-based Debloat ---
debloat_arch() {
  echo "## Debloating Arch-based system..."

  # Remove mostly useless packages
  echo "Removing unnecessary KDE packages..."
  sudo pacman -Rns --noconfirm kcontacts 2>/dev/null || true
  sudo pacman -Rns --noconfirm kpeople 2>/dev/null || true

  # Remove deprecated packages
  echo "Removing deprecated packages..."
  sudo pacman -Rncs --noconfirm -q cachy-browser 2>/dev/null || true
  sudo pacman -Rncs --noconfirm cachyos-v4-mirrorlist 2>/dev/null || true

  # Remove telemetry
  echo "Removing pkgstats (telemetry)..."
  if systemctl list-unit-files | grep -qx "pkgstats.timer"; then
    sudo systemctl stop "pkgstats.timer" &>/dev/null || true
    sudo systemctl disable "pkgstats.timer" 2>/dev/null || true
  fi
  if pacman -Qq pkgstats &>/dev/null; then
    sudo pacman -Rcns --noconfirm -q pkgstats &>/dev/null || true
  fi

  # Disable unnecessary services
  echo "Disabling unnecessary services..."
  sudo systemctl disable bluetooth.service 2>/dev/null || true
  sudo systemctl disable avahi-daemon.service 2>/dev/null || true
  if systemctl list-unit-files | grep -q printer.service; then
    sudo systemctl disable printer.service 2>/dev/null || true
    echo "Printer service disabled."
  fi

  # Configure fwupd
  if [[ -f /etc/fwupd/fwupd.conf ]]; then
    sudo grep -xqF -- 'P2pPolicy=nothing' '/etc/fwupd/fwupd.conf' || \
      echo 'P2pPolicy=nothing' | sudo tee -a '/etc/fwupd/fwupd.conf' >/dev/null
  fi

  # Disable UFW logging
  if command -v ufw &>/dev/null; then
    sudo ufw logging off 2>/dev/null || true
  fi
}

# --- Debian-based Debloat ---
debloat_debian() {
  echo "## Debloating Debian-based system..."

  # Remove LibreOffice (if not needed)
  echo "Removing LibreOffice..."
  sudo apt-get purge -y libreoffice* 2>/dev/null || true

  # Remove telemetry and reporting tools
  echo "Removing telemetry packages..."
  sudo apt-get purge -y reportbug python3-reportbug reportbug-gtk \
    apport whoopsie popularity-contest 2>/dev/null || true

  # Disable Popularity Contest
  echo "Disabling Popularity Contest..."
  if [[ -f /etc/popularity-contest.conf ]]; then
    sudo sed -i '/^PARTICIPATE=/d;$aPARTICIPATE=no' "/etc/popularity-contest.conf"
  fi

  # Disable popularity-contest cronjob
  if [[ -f /etc/cron.daily/popularity-contest ]]; then
    if [[ -x /etc/cron.daily/popularity-contest ]]; then
      sudo chmod -x "/etc/cron.daily/popularity-contest"
      echo "Disabled popularity-contest cronjob."
    fi
  fi

  # Cleanup
  echo "Running apt cleanup..."
  sudo apt-get autoclean -y
  sudo apt-get autoremove -y
}

# --- Main Execution ---
main() {
  local platform
  platform=$(detect_platform)

  echo "Detected platform: $platform"
  echo

  case "$platform" in
    arch)
      debloat_arch
      ;;
    debian)
      debloat_debian
      ;;
    *)
      echo "Error: Unsupported platform. This script supports Arch and Debian-based systems only." >&2
      exit 1
      ;;
  esac

  echo
  echo "Debloat complete!"
  echo "Press any key to exit."
  read -n 1 -s
}

main "$@"
