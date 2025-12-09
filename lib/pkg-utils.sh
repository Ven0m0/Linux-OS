#!/usr/bin/env bash
# Package manager detection and utilities for Linux-OS scripts
# Source this file: source "${BASH_SOURCE%/*}/../lib/pkg-utils.sh"

# Prevent multiple sourcing
[[ -n ${LINUX_OS_PKG_UTILS_LOADED:-} ]] && return 0
readonly LINUX_OS_PKG_UTILS_LOADED=1

# Ensure common.sh is loaded for helper functions
if [[ -z ${LINUX_OS_COMMON_LOADED:-} ]]; then
  source "${BASH_SOURCE%/*}/common.sh"
fi

# ============================================================================
# PACKAGE MANAGER DETECTION (CACHED)
# ============================================================================

# Cached package manager values
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()

# Detect package manager and cache results
# Outputs: package_manager_name followed by AUR options (one per line)
# Usage:
#   mapfile -t result < <(detect_pkg_manager)
#   pkgmgr=${result[0]}
#   aur_opts=("${result[@]:1}")
detect_pkg_manager() {
  # Return cached values if available
  if [[ -n $_PKG_MGR_CACHED ]]; then
    printf '%s\n' "$_PKG_MGR_CACHED"
    printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
    return 0
  fi

  local pkgmgr

  # Detect Arch-based package managers
  if has paru; then
    pkgmgr=paru
    _AUR_OPTS_CACHED=(--batchinstall --combinedupgrade --nokeepsrc)
  elif has yay; then
    pkgmgr=yay
    _AUR_OPTS_CACHED=(--answerclean y --answerdiff n --answeredit n --answerupgrade y)
  elif has pacman; then
    pkgmgr=pacman
    _AUR_OPTS_CACHED=()
  # Detect Debian-based package managers
  elif has apt; then
    pkgmgr=apt
    _AUR_OPTS_CACHED=()
  elif has apt-get; then
    pkgmgr=apt-get
    _AUR_OPTS_CACHED=()
  else
    err "No supported package manager found"
    return 1
  fi

  _PKG_MGR_CACHED=$pkgmgr
  printf '%s\n' "$pkgmgr"
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

# Get cached package manager name (detect if not already cached)
# Usage: pkgmgr=$(get_pkg_manager)
get_pkg_manager() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

# Get cached AUR helper options
# Usage: mapfile -t aur_opts < <(get_aur_opts)
get_aur_opts() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

# ============================================================================
# STANDARD AUR HELPER FLAGS
# ============================================================================

# Get standard AUR helper installation flags
# Usage: mapfile -t flags < <(get_aur_install_flags)
get_aur_install_flags() {
  printf '%s\n' \
    --needed \
    --noconfirm \
    --removemake \
    --cleanafter \
    --sudoloop \
    --skipreview \
    --batchinstall
}

# ============================================================================
# PACKAGE OPERATIONS
# ============================================================================

# Install packages using detected package manager
# Usage: pkg_install package1 package2 package3
pkg_install() {
  [[ $# -eq 0 ]] && return 0

  local pkgmgr
  pkgmgr=$(get_pkg_manager)

  case $pkgmgr in
    paru | yay)
      local -a opts
      mapfile -t opts < <(get_aur_opts)
      "$pkgmgr" -S --needed --noconfirm "${opts[@]}" "$@"
      ;;
    pacman)
      run_priv pacman -S --needed --noconfirm "$@"
      ;;
    apt | apt-get)
      run_priv "$pkgmgr" install -y "$@"
      ;;
    *)
      die "Unsupported package manager: $pkgmgr"
      ;;
  esac
}

# Remove packages using detected package manager
# Usage: pkg_remove package1 package2 package3
pkg_remove() {
  [[ $# -eq 0 ]] && return 0

  local pkgmgr
  pkgmgr=$(get_pkg_manager)

  case $pkgmgr in
    paru | yay | pacman)
      run_priv pacman -Rns --noconfirm "$@" 2>/dev/null \
        || run_priv pacman -Rn --noconfirm "$@"
      ;;
    apt | apt-get)
      run_priv "$pkgmgr" remove --purge -y "$@"
      ;;
    *)
      die "Unsupported package manager: $pkgmgr"
      ;;
  esac
}

# Check if package is installed
# Usage: pkg_installed package_name && echo "installed"
pkg_installed() {
  local pkg=${1:?}
  local pkgmgr
  pkgmgr=$(get_pkg_manager)

  case $pkgmgr in
    paru | yay | pacman)
      pacman -Q "$pkg" &>/dev/null
      ;;
    apt | apt-get)
      dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'
      ;;
    *)
      return 1
      ;;
  esac
}

# Update package database
# Usage: pkg_update
pkg_update() {
  local pkgmgr
  pkgmgr=$(get_pkg_manager)

  case $pkgmgr in
    paru | yay)
      local -a opts
      mapfile -t opts < <(get_aur_opts)
      "$pkgmgr" -Sy --noconfirm "${opts[@]}"
      ;;
    pacman)
      run_priv pacman -Sy --noconfirm
      ;;
    apt | apt-get)
      run_priv "$pkgmgr" update
      ;;
    *)
      die "Unsupported package manager: $pkgmgr"
      ;;
  esac
}

# Upgrade all packages
# Usage: pkg_upgrade
pkg_upgrade() {
  local pkgmgr
  pkgmgr=$(get_pkg_manager)

  case $pkgmgr in
    paru | yay)
      local -a opts
      mapfile -t opts < <(get_aur_opts)
      "$pkgmgr" -Syu --noconfirm "${opts[@]}"
      ;;
    pacman)
      run_priv pacman -Syu --noconfirm
      ;;
    apt | apt-get)
      run_priv "$pkgmgr" upgrade -y
      ;;
    *)
      die "Unsupported package manager: $pkgmgr"
      ;;
  esac
}

# Clean package cache
# Usage: pkg_clean
pkg_clean() {
  local pkgmgr
  pkgmgr=$(get_pkg_manager)

  case $pkgmgr in
    paru | yay | pacman)
      run_priv paccache -rk0 -q 2>/dev/null || :
      run_priv pacman -Scc --noconfirm 2>/dev/null || :
      has paru && paru -Scc --noconfirm 2>/dev/null || :
      ;;
    apt | apt-get)
      run_priv "$pkgmgr" clean -y 2>/dev/null || :
      run_priv "$pkgmgr" autoclean 2>/dev/null || :
      run_priv "$pkgmgr" autoremove --purge -y 2>/dev/null || :
      ;;
    *)
      warn "Clean not supported for: $pkgmgr"
      ;;
  esac
}

# Remove orphaned packages
# Usage: pkg_autoremove
pkg_autoremove() {
  local pkgmgr
  pkgmgr=$(get_pkg_manager)

  case $pkgmgr in
    paru | yay | pacman)
      local orphans
      orphans=$(pacman -Qdtq 2>/dev/null || :)
      [[ -n $orphans ]] && run_priv pacman -Rns --noconfirm "$orphans" || :
      ;;
    apt | apt-get)
      run_priv "$pkgmgr" autoremove --purge -y
      ;;
    *)
      warn "Autoremove not supported for: $pkgmgr"
      ;;
  esac
}

# ============================================================================
# BUILD ENVIRONMENT SETUP
# ============================================================================

# Setup optimized build environment for native compilation
# Usage: setup_build_env
setup_build_env() {
  # C/C++ compiler flags
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"

  # Parallel build flags
  local jobs
  jobs=$(nproc 2>/dev/null || echo 4)
  export MAKEFLAGS="-j${jobs}"
  export NINJAFLAGS="-j${jobs}"

  # Compiler selection (prefer LLVM toolchain)
  if has clang && has clang++; then
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export NM=llvm-nm
    export RANLIB=llvm-ranlib
  fi

  # Rust compiler flags
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat"
  has ld.lld && export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"

  log "Build environment configured: ${jobs} parallel jobs, native optimization"
}

# ============================================================================
# RETURN SUCCESS
# ============================================================================

return 0
