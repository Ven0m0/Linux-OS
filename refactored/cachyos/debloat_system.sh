#!/usr/bin/env bash
# Unified Debloat Script for Arch-based and Debian-based systems
# Refactored version with improved structure and maintainability
# Removes unnecessary packages and disables telemetry services
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
sudo -v

# --- Colors ---
readonly RED=$'\e[31m'
readonly GRN=$'\e[32m'
readonly YLW=$'\e[33m'
readonly DEF=$'\e[0m'

# --- Helper Functions ---
has() {
    command -v -- "$1" &>/dev/null
}

msg() {
    printf '%b%s%b\n' "$GRN" "$*" "$DEF"
}

warn() {
    printf '%b%s%b\n' "$YLW" "$*" "$DEF"
}

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
    msg "## Debloating Arch-based system..."
    
    # Remove mostly useless packages
    msg "Removing unnecessary packages..."
    sudo pacman -Rncs --noconfirm kcontacts kpeople cachy-browser cachyos-v4-mirrorlist || :
    
    # Remove telemetry
    msg "Removing pkgstats (telemetry)..."
    if systemctl list-unit-files | grep -qx "pkgstats.timer"; then
        sudo systemctl disable --now "pkgstats.timer" 2>/dev/null || :
    fi
    if pacman -Qq pkgstats &>/dev/null; then
        sudo pacman -Rcns --noconfirm pkgstats &>/dev/null || :
    fi
    
    # Disable unnecessary services
    msg "Disabling unnecessary services..."
    sudo systemctl disable --now bluetooth avahi-daemon printer || :
    
    # Configure fwupd
    if [[ -f /etc/fwupd/fwupd.conf ]]; then
        if ! grep -xqF -- 'P2pPolicy=nothing' '/etc/fwupd/fwupd.conf'; then
            echo 'P2pPolicy=nothing' | sudo tee -a '/etc/fwupd/fwupd.conf' >/dev/null
        fi
    fi
    
    # Disable UFW logging
    if has ufw; then
        sudo ufw logging off 2>/dev/null || :
    fi
}

# --- Debian-based Debloat ---
debloat_debian() {
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
            echo 'PARTICIPATE=no' | sudo tee -a /etc/popularity-contest.conf >/dev/null
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

# --- Main Execution ---
main() {
    local platform
    platform=$(detect_platform)
    msg "Detected platform: $platform"
    
    case "$platform" in
        arch) debloat_arch ;;
        debian) debloat_debian ;;
        *)
            printf '%b%s%b\n' "$RED" "Error: Unsupported platform. This script supports Arch and Debian-based systems only." "$DEF" >&2
            exit 1
            ;;
    esac
    
    msg "\nDebloat complete!"
}

main "$@"