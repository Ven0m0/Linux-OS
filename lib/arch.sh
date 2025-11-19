#!/usr/bin/env bash
# Linux-OS Arch Linux Library
# Platform-specific functions for Arch Linux / CachyOS
# Requires: lib/base.sh
#
# This library provides:
# - Package manager detection (pacman/paru/yay)
# - Build environment setup
# - System maintenance functions
# - SQLite optimization
# - Process management
# - Browser profile detection

[[ -z ${_BASE_LIB_LOADED:-} ]] && {
  echo "Error: lib/base.sh must be sourced before lib/arch.sh" >&2
  exit 1
}

# ============================================================================
# Package Manager Detection & Caching
# ============================================================================

# Cache variables
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()

# Detect and return best available AUR helper or pacman
# Returns: Package manager name and options (multi-line)
detect_pkg_manager() {
  # Return cached result if available
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
# Usage: pkgmgr=$(get_pkg_manager)
get_pkg_manager() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

# Get AUR options for the detected package manager
# Usage: mapfile -t aur_opts < <(get_aur_opts)
get_aur_opts() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

# ============================================================================
# Build Environment Setup
# ============================================================================

# Setup optimized build environment for Arch Linux
# Sets compiler flags, parallel build settings, and tool preferences
setup_build_env() {
  # Source makepkg.conf if available
  [[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf &>/dev/null

  # Rust optimization flags
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"

  # C/C++ optimization flags
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"

  # Linker optimization flags
  export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,--gc-sections"

  # Cargo configuration
  export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/cargo-target}"
  export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
  export CARGO_HTTP_MULTIPLEXING=true
  export CARGO_NET_GIT_FETCH_WITH_CLI=true
  export CARGO_CACHE_RUSTC_INFO=1
  export RUSTC_BOOTSTRAP=1

  # Parallel build settings
  local nproc_count
  nproc_count=$(get_nproc)
  export MAKEFLAGS="-j${nproc_count}"
  export NINJAFLAGS="-j${nproc_count}"

  # Compiler selection (prefer LLVM toolchain)
  if has clang && has clang++; then
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export NM=llvm-nm
    export RANLIB=llvm-ranlib

    # Use lld linker if available
    if has ld.lld; then
      export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
    fi
  fi

  # Initialize dbus if available
  has dbus-launch && eval "$(dbus-launch 2>/dev/null || :)"
}

# ============================================================================
# System Maintenance Functions
# ============================================================================

# Run system maintenance commands safely
# Usage: run_system_maintenance <command> [args...]
run_system_maintenance() {
  local cmd=$1
  shift
  local args=("$@")

  has "$cmd" || return 0

  case "$cmd" in
    modprobed-db)
      "$cmd" store &>/dev/null || :
      ;;
    hwclock | updatedb | chwd)
      run_priv "$cmd" "${args[@]}" &>/dev/null || :
      ;;
    mandb)
      run_priv "$cmd" -q &>/dev/null || mandb -q &>/dev/null || :
      ;;
    *)
      run_priv "$cmd" "${args[@]}" &>/dev/null || :
      ;;
  esac
}

# Cleanup pacman lock file
# Usage: cleanup_pacman_lock
cleanup_pacman_lock() {
  local lockfile="/var/lib/pacman/db.lck"
  if [[ -f $lockfile ]]; then
    warn "Removing stale pacman lock file"
    run_priv rm -f "$lockfile"
  fi
}

# ============================================================================
# SQLite Maintenance
# ============================================================================

# Vacuum a single SQLite database and return bytes saved
# Usage: saved=$(vacuum_sqlite "path/to/db.sqlite")
vacuum_sqlite() {
  local db=$1 s_old s_new

  [[ -f $db ]] || {
    printf '0\n'
    return
  }

  # Skip if probably open
  [[ -f ${db}-wal || -f ${db}-journal ]] && {
    printf '0\n'
    return
  }

  # Validate it's actually a SQLite database file
  if ! head -c 16 "$db" 2>/dev/null | grep -q 'SQLite format 3'; then
    printf '0\n'
    return
  fi

  s_old=$(stat -c%s "$db" 2>/dev/null) || {
    printf '0\n'
    return
  }

  # VACUUM already rebuilds indices, making REINDEX redundant
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || {
    printf '0\n'
    return
  }

  s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
  printf '%d\n' "$((s_old - s_new))"
}

# Clean SQLite databases in current working directory
# Usage: clean_sqlite_dbs
clean_sqlite_dbs() {
  local total=0 db saved

  # Batch file type checks to reduce subprocess calls
  while IFS= read -r -d '' db; do
    # Skip non-regular files early
    [[ -f $db ]] || continue
    saved=$(vacuum_sqlite "$db" || printf '0')
    ((saved > 0)) && total=$((total + saved))
  done < <(find0 . -maxdepth 1 -type f)

  ((total > 0)) && ok "Vacuumed SQLite DBs, saved $((total / 1024)) KB"
}

# ============================================================================
# Process Management
# ============================================================================

# Wait for processes to exit, kill if timeout
# Usage: ensure_not_running_any "process1" "process2" ...
ensure_not_running_any() {
  local timeout=6 p
  # Optimized: Use single pgrep with pattern instead of multiple calls
  local pattern
  pattern=$(printf '%s|' "$@")
  pattern=${pattern%|}

  # Quick check if any processes are running
  pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return

  # Show waiting message for found processes
  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &>/dev/null && warn "Waiting for ${p} to exit..."
  done

  # Single wait loop checking all processes with one pgrep call
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return
    sleep 1
  done

  # Kill any remaining processes (single pkill call)
  if pgrep -x -u "$USER" -f "$pattern" &>/dev/null; then
    err "Killing remaining processes..."
    pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :
    sleep 1
  fi
}

# ============================================================================
# Browser Profile Detection
# ============================================================================

# Firefox-family profile discovery
# Usage: profile_path=$(foxdir "$HOME/.mozilla/firefox")
foxdir() {
  local base=$1 p
  [[ -d $base ]] || return 1

  # Check installs.ini first
  if [[ -f $base/installs.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini")
    [[ -n $p && -d $base/$p ]] && {
      printf '%s\n' "$base/$p"
      return 0
    }
  fi

  # Check profiles.ini
  if [[ -f $base/profiles.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{s=0} /^\[Profile[0-9]+\]/{s=1} s&&/^Default=1/{d=1} s&&/^Path=/{if(d){print $2;exit}}' "$base/profiles.ini")
    [[ -n $p && -d $base/$p ]] && {
      printf '%s\n' "$base/$p"
      return 0
    }
  fi

  return 1
}

# List all Mozilla profiles in a base directory
# Usage: mapfile -t profiles < <(mozilla_profiles "$HOME/.mozilla/firefox")
mozilla_profiles() {
  local base=$1 p
  declare -A seen
  [[ -d $base ]] || return 0

  # Process installs.ini using awk for efficiency
  if [[ -f $base/installs.ini ]]; then
    while IFS= read -r p; do
      [[ -d $base/$p && -z ${seen[$p]:-} ]] && {
        printf '%s\n' "$base/$p"
        seen[$p]=1
      }
    done < <(awk -F= '/^Default=/ {print $2}' "$base/installs.ini")
  fi

  # Process profiles.ini using awk for efficiency
  if [[ -f $base/profiles.ini ]]; then
    while IFS= read -r p; do
      [[ -d $base/$p && -z ${seen[$p]:-} ]] && {
        printf '%s\n' "$base/$p"
        seen[$p]=1
      }
    done < <(awk -F= '/^Path=/ {print $2}' "$base/profiles.ini")
  fi
}

# Chromium roots (native/flatpak/snap)
# Usage: mapfile -t roots < <(chrome_roots_for "chromium")
chrome_roots_for() {
  case "$1" in
    chrome)
      printf '%s\n' \
        "$HOME/.config/google-chrome" \
        "$HOME/.var/app/com.google.Chrome/config/google-chrome" \
        "$HOME/snap/google-chrome/current/.config/google-chrome"
      ;;
    chromium)
      printf '%s\n' \
        "$HOME/.config/chromium" \
        "$HOME/.var/app/org.chromium.Chromium/config/chromium" \
        "$HOME/snap/chromium/current/.config/chromium"
      ;;
    brave)
      printf '%s\n' \
        "$HOME/.config/BraveSoftware/Brave-Browser" \
        "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" \
        "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser"
      ;;
    opera)
      printf '%s\n' \
        "$HOME/.config/opera" \
        "$HOME/.config/opera-beta" \
        "$HOME/.config/opera-developer"
      ;;
    *)
      :
      ;;
  esac
}

# List Default + Profile * dirs under a Chromium root
# Usage: mapfile -t profiles < <(chrome_profiles "$chrome_root")
chrome_profiles() {
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "* ; do
    [[ -d $d ]] && printf '%s\n' "$d"
  done
}

# ============================================================================
# Cargo Cache Management
# ============================================================================

# Clean Cargo cache
# Usage: clean_cargo_cache
clean_cargo_cache() {
  if has cargo; then
    cargo cache --autoclean 2>/dev/null || :
    [[ -d ~/.cargo/registry ]] && find ~/.cargo/registry -type f -name "*.crate" -delete 2>/dev/null || :
  fi
}

# ============================================================================
# Library Load Confirmation
# ============================================================================

_ARCH_LIB_LOADED=1
return 0
