#!/usr/bin/env bash
# lib/arch.sh - Arch Linux shared library
# Provides: package manager detection, build environment, Arch-specific helpers
# Requires: lib/core.sh
# shellcheck disable=SC2034
[[ -n ${_LIB_ARCH_LOADED:-} ]] && return 0
_LIB_ARCH_LOADED=1

# Source core library if not loaded
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=lib/core.sh
[[ -z ${_LIB_CORE_LOADED:-} ]] && source "${SCRIPT_DIR}/core.sh"

#============ Package Manager Detection ============
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()

# Detect and cache package manager
detect_pkg_manager(){
  if [[ -n $_PKG_MGR_CACHED ]]; then
    printf '%s\n' "$_PKG_MGR_CACHED"
    printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
    return 0
  fi
  local pkgmgr
  if has paru; then
    pkgmgr=paru
    _AUR_OPTS_CACHED=(--batchinstall --combinedupgrade --nokeepsrc)
  elif has yay; then
    pkgmgr=yay
    _AUR_OPTS_CACHED=(--answerclean y --answerdiff n --answeredit n --answerupgrade y)
  else
    pkgmgr=pacman
    _AUR_OPTS_CACHED=()
  fi
  _PKG_MGR_CACHED=$pkgmgr
  printf '%s\n' "$pkgmgr"
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

# Get package manager name only (without options)
get_pkg_manager(){
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

# Get AUR options for the detected package manager
get_aur_opts(){
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

# Check if AUR helper is available
is_aur_available(){
  [[ -z $_PKG_MGR_CACHED ]] && detect_pkg_manager >/dev/null
  [[ $_PKG_MGR_CACHED != pacman ]]
}

# Remove pacman lock file
cleanup_pacman_lock(){
  sudo rm -f /var/lib/pacman/db.lck &>/dev/null || :
}

#============ Build Environment Setup ============
# Setup optimized build environment for Arch Linux
setup_build_env(){
  # Source makepkg.conf if available
  [[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf &>/dev/null

  # Rust optimization flags
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"

  # C/C++ optimization flags
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"

  # Linker optimization flags
  export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"

  # Cargo configuration
  export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
  export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_CACHE_RUSTC_INFO=1 RUSTC_BOOTSTRAP=1

  # Parallel build settings
  local nproc_count
  nproc_count=$(nproc 2>/dev/null || echo 4)
  export MAKEFLAGS="-j${nproc_count}"
  export NINJAFLAGS="-j${nproc_count}"

  # Compiler selection (prefer LLVM toolchain)
  if has clang && has clang++; then
    export CC=clang CXX=clang++ AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib
    has ld.lld && export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
  fi

  # Initialize dbus if available
  has dbus-launch && eval "$(dbus-launch 2>/dev/null || :)"
}

#============ System Maintenance Functions ============
# Run system maintenance commands safely
run_system_maintenance(){
  local cmd=$1
  shift
  local args=("$@")
  has "$cmd" || return 0
  case "$cmd" in
  modprobed-db) "$cmd" store &>/dev/null || : ;;
  hwclock | updatedb | chwd) sudo "$cmd" "${args[@]}" &>/dev/null || : ;;
  mandb) sudo "$cmd" -q &>/dev/null || mandb -q &>/dev/null || : ;;
  *) sudo "$cmd" "${args[@]}" &>/dev/null || : ;;
  esac
}

#============ Initramfs Helpers ============
# Rebuild initramfs using available tool
rebuild_initramfs(){
  if has update-initramfs; then
    sudo update-initramfs || :
  elif has limine-mkinitcpio; then
    sudo limine-mkinitcpio || :
  elif has mkinitcpio; then
    sudo mkinitcpio -P || :
  elif [[ -x /usr/lib/booster/regenerate_images ]]; then
    sudo /usr/lib/booster/regenerate_images || :
  elif has dracut-rebuild; then
    sudo dracut-rebuild || :
  elif has dracut; then
    sudo dracut --regenerate-all --force || :
  else
    warn "No initramfs generator found"
    return 1
  fi
}
