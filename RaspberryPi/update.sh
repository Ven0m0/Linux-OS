#!/usr/bin/env bash
# System update script for Raspberry Pi / Debian-based systems
# Updates system packages, firmware, and runs DietPi updates if available

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/debian.sh" || exit 1
source "${SCRIPT_DIR}/../lib/ui.sh" || exit 1

# Set Debian-specific environment
export DEBIAN_FRONTEND=noninteractive
export PRUNE_MODULES=1
export SKIP_VCLIBS=1

# Initialize working directory
init_workdir

# ============================================================================
# Main Update Function
# ============================================================================

main() {
  # Print banner
  print_named_banner "update" "Meow (> ^ <)"

  # Load DietPi globals if available
  load_dietpi_globals

  # Sync before starting
  sync

  # Clean APT lists before update
  info "Cleaning APT lists"
  run_priv rm -rf --preserve-root -- /var/lib/apt/lists/*

  # Get best APT tool
  local apt_tool
  apt_tool=$(get_apt_tool)

  # Perform system update
  section "Updating System Packages"

  case "$apt_tool" in
    nala)
      info "Using nala for updates"
      run_priv nala upgrade --no-install-recommends
      run_priv nala clean
      run_priv nala autoremove
      run_priv nala autopurge
      ;;
    apt-fast)
      info "Using apt-fast for updates"
      run_priv apt-fast update -y --allow-releaseinfo-change
      run_priv apt-fast upgrade -y --no-install-recommends
      run_priv apt-fast dist-upgrade -y --no-install-recommends
      clean_apt_cache
      run_priv apt-fast autopurge -yq 2>/dev/null || :
      ;;
    *)
      info "Using apt-get for updates"
      run_priv apt-get update -y --allow-releaseinfo-change \
        -o Acquire::Languages=none \
        -o APT::Get::Fix-Missing=true \
        -o APT::Get::Fix-Broken=true

      run_priv apt-get dist-upgrade -y \
        -o Acquire::Languages=none \
        -o APT::Get::Fix-Missing=true \
        -o APT::Get::Fix-Broken=true

      run_priv apt-get full-upgrade -y \
        -o Acquire::Languages=none \
        -o APT::Get::Fix-Missing=true \
        -o APT::Get::Fix-Broken=true

      clean_apt_cache
      ;;
  esac

  # Fix broken packages
  info "Checking for broken packages"
  run_priv dpkg --configure -a >/dev/null

  ok "System packages updated"

  # DietPi updates
  if is_dietpi; then
    section "Running DietPi Updates"
    run_dietpi_update || warn "DietPi update failed"
  fi

  # Pi-hole update
  if has pihole; then
    info "Updating Pi-hole"
    run_priv pihole -up
  fi

  # Raspberry Pi firmware updates
  if is_raspberry_pi; then
    section "Updating Raspberry Pi Firmware"

    # Update EEPROM
    if has rpi-eeprom-update; then
      info "Updating EEPROM"
      run_priv rpi-eeprom-update -a
    fi

    # Update kernel/firmware (use with caution)
    if has rpi-update; then
      info "Updating kernel/firmware"
      run_priv env \
        SKIP_WARNING=1 \
        RPI_UPDATE_UNSUPPORTED=0 \
        PRUNE_MODULES=1 \
        SKIP_VCLIBS=1 \
        rpi-update 2>/dev/null || :
    fi
  fi

  # Done!
  printf '\n'
  ok "All updates completed! ✅"
  printf '\n'
}

main "$@"
