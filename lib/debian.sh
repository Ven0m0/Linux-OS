#!/usr/bin/env bash
# Linux-OS Debian/Raspbian Library
# Platform-specific functions for Debian-based systems (RaspberryPi)
# Requires: lib/base.sh
#
# This library provides:
# - APT package manager utilities
# - DietPi integration functions
# - Debian-specific system configuration

[[ -z ${_BASE_LIB_LOADED:-} ]] && {
  echo "Error: lib/base.sh must be sourced before lib/debian.sh" >&2
  exit 1
}

# Set Debian-specific environment variables
export DEBIAN_FRONTEND=noninteractive
export HOME="/home/${SUDO_USER:-$USER}"

# ============================================================================
# APT Package Manager Detection
# ============================================================================

# Cache for APT tool
_APT_TOOL_CACHED=""

# Detect best available APT frontend
# Checks for: nala, apt-fast, apt
# Usage: apt_tool=$(get_apt_tool)
get_apt_tool() {
  # Return cached if available
  if [[ -n $_APT_TOOL_CACHED ]]; then
    printf '%s' "$_APT_TOOL_CACHED"
    return 0
  fi

  local tool
  if has nala; then
    tool=nala
  elif has apt-fast; then
    tool=apt-fast
  elif has apt-get; then
    tool=apt-get
  else
    die "No APT tool found"
  fi

  _APT_TOOL_CACHED=$tool
  printf '%s' "$tool"
}

# Run APT command with best available tool
# Usage: run_apt update
# Usage: run_apt install package1 package2
run_apt() {
  local apt_tool
  apt_tool=$(get_apt_tool)
  run_priv "$apt_tool" "$@"
}

# ============================================================================
# APT Cleanup Functions
# ============================================================================

# Clean APT package manager cache
# Removes cached package files and orphaned packages
clean_apt_cache() {
  local apt_tool
  apt_tool=$(get_apt_tool)

  run_priv "$apt_tool" clean -yq
  run_priv "$apt_tool" autoclean -yq
  run_priv "$apt_tool" autoremove --purge -yq
}

# Fix broken APT packages
# Usage: fix_apt_packages
fix_apt_packages() {
  local apt_tool
  apt_tool=$(get_apt_tool)

  run_priv dpkg --configure -a
  run_priv "$apt_tool" install -f -y
}

# Update APT package lists
# Usage: update_apt
update_apt() {
  local apt_tool
  apt_tool=$(get_apt_tool)
  run_priv "$apt_tool" update
}

# Upgrade all packages
# Usage: upgrade_apt_packages
upgrade_apt_packages() {
  local apt_tool
  apt_tool=$(get_apt_tool)

  if [[ $apt_tool == "nala" ]]; then
    run_priv nala upgrade -y
  elif [[ $apt_tool == "apt-fast" ]]; then
    run_priv apt-fast dist-upgrade -y
  else
    run_priv apt-get dist-upgrade -y
  fi
}

# ============================================================================
# DietPi Integration
# ============================================================================

# Check if running on DietPi
# Usage: is_dietpi && do_something
is_dietpi() {
  [[ -f /boot/dietpi/func/dietpi-globals ]]
}

# Load DietPi globals if available
# Usage: load_dietpi_globals
load_dietpi_globals() {
  if is_dietpi; then
    # shellcheck disable=SC1091
    source /boot/dietpi/func/dietpi-globals &>/dev/null || :
  fi
}

# Run DietPi update
# Usage: run_dietpi_update
run_dietpi_update() {
  if ! is_dietpi; then
    return 0
  fi

  if has dietpi-update; then
    run_priv dietpi-update 1
  elif [[ -x /boot/dietpi/dietpi-update ]]; then
    run_priv /boot/dietpi/dietpi-update 1
  else
    warn "DietPi detected but dietpi-update not found"
    return 1
  fi
}

# Run DietPi cleanup commands
# Usage: run_dietpi_cleanup
run_dietpi_cleanup() {
  if ! is_dietpi; then
    return 0
  fi

  # DietPi log cleaner
  if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then
    run_priv /boot/dietpi/func/dietpi-logclear 2 &>/dev/null || \
      G_SUDO dietpi-logclear 2 &>/dev/null || :
  fi

  # DietPi system cleaner
  if [[ -f /boot/dietpi/func/dietpi-cleaner ]]; then
    run_priv /boot/dietpi/func/dietpi-cleaner 2 &>/dev/null || \
      G_SUDO dietpi-cleaner 2 &>/dev/null || :
  fi
}

# ============================================================================
# Debian System Configuration
# ============================================================================

# Configure dpkg to exclude documentation
# Sets up dpkg to not install docs/man pages in future package installations
configure_dpkg_nodoc() {
  local dpkg_config='path-exclude /usr/share/doc/*
path-exclude /usr/share/help/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
# we need to keep copyright files for legal reasons
path-include /usr/share/doc/*/copyright'

  echo "$dpkg_config" | run_priv tee /etc/dpkg/dpkg.cfg.d/01_nodoc >/dev/null
  ok "Configured dpkg to exclude documentation in future installations"
}

# Remove system documentation files
# Removes man pages, docs, locales (except en_GB), and related files
clean_documentation() {
  info "Removing documentation files..."
  run_priv find /usr/share/doc/ -depth -type f ! -name copyright -delete 2>/dev/null || :
  run_priv find /usr/share/doc/ -name '*.gz' -delete 2>/dev/null || :
  run_priv find /usr/share/doc/ -name '*.pdf' -delete 2>/dev/null || :
  run_priv find /usr/share/doc/ -name '*.tex' -delete 2>/dev/null || :
  run_priv find /usr/share/doc/ -type d -empty -delete 2>/dev/null || :

  info "Removing man pages and related files..."
  clean_with_sudo \
    /usr/share/groff/* \
    /usr/share/info/* \
    /usr/share/lintian/* \
    /usr/share/linda/* \
    /var/cache/man/* \
    /usr/share/man/*
}

# ============================================================================
# Raspberry Pi Specific Functions
# ============================================================================

# Check if running on Raspberry Pi
# Usage: is_raspberry_pi && do_something
is_raspberry_pi() {
  [[ -f /proc/device-tree/model ]] && \
    grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null
}

# Get Raspberry Pi model
# Usage: model=$(get_pi_model)
get_pi_model() {
  if [[ -f /proc/device-tree/model ]]; then
    cat /proc/device-tree/model | tr -d '\0'
  else
    echo "Unknown"
  fi
}

# Check if Raspberry Pi has 64-bit OS
# Usage: is_pi_64bit && do_something
is_pi_64bit() {
  [[ $(uname -m) == "aarch64" ]]
}

# ============================================================================
# F2FS Filesystem Support
# ============================================================================

# Check if F2FS is available
# Usage: has_f2fs && do_something
has_f2fs() {
  has mkfs.f2fs && \
    grep -q f2fs /proc/filesystems 2>/dev/null
}

# ============================================================================
# Library Load Confirmation
# ============================================================================

_DEBIAN_LIB_LOADED=1
return 0
