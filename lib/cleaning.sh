#!/usr/bin/env bash
# Linux-OS Cleaning Library
# System cleaning functions for cache, logs, and temporary files
# Requires: lib/base.sh
#
# This library provides:
# - Cache cleanup (system, user, package managers)
# - Log rotation and cleanup
# - Browser data cleanup
# - Container cleanup (Docker/Podman)
# - Package manager cleanup
# - SQLite optimization

[[ -z ${_BASE_LIB_LOADED:-} ]] && {
  echo "Error: lib/base.sh must be sourced before lib/cleaning.sh" >&2
  exit 1
}

# ============================================================================
# System Cache Cleanup
# ============================================================================

# Clean system cache directories
# Removes temporary files and user/root caches
clean_cache_dirs() {
  info "Cleaning system cache directories"

  clean_with_sudo \
    /tmp/* \
    /var/tmp/* \
    /var/cache/apt/archives/* \
    /root/.cache/*

  clean_paths \
    ~/.cache/* \
    ~/.thumbnails/* \
    ~/.cache/thumbnails/*
}

# Clean trash directories
# Clears trash for user, root, and snap/flatpak applications
clean_trash() {
  info "Cleaning trash directories"

  clean_paths \
    ~/.local/share/Trash/* \
    ~/snap/*/*/.local/share/Trash/* \
    ~/.var/app/*/data/Trash/*

  clean_with_sudo /root/.local/share/Trash/*
}

# ============================================================================
# Log Cleanup
# ============================================================================

# Clean systemd journal logs
# Reduces journal size and removes old log files
clean_journal_logs() {
  info "Cleaning systemd journal logs"

  run_priv journalctl --rotate --vacuum-size=1 --flush --sync -q 2>/dev/null || :
  clean_with_sudo /run/log/journal/* /var/log/journal/*
  run_priv systemd-tmpfiles --clean 2>/dev/null || :
}

# Clean crash dumps and core dumps
# Removes system crash reports
clean_crash_dumps() {
  info "Cleaning crash dumps"

  if has coredumpctl; then
    run_priv coredumpctl --quiet --no-legend clean 2>/dev/null || :
  fi

  clean_with_sudo \
    /var/crash/* \
    /var/lib/systemd/coredump/*
}

# Clean shell and Python history files
# Removes bash and Python history for current user and root
clean_history_files() {
  info "Cleaning history files"

  clean_paths \
    ~/.python_history \
    ~/.bash_history

  clean_with_sudo \
    /root/.python_history \
    /root/.bash_history

  history -c 2>/dev/null || :
}

# ============================================================================
# Package Manager Cache Cleanup
# ============================================================================

# Clean package manager caches based on available tools
clean_package_caches() {
  info "Cleaning package manager caches"

  # Pacman cache (Arch)
  if has pacman; then
    run_priv paccache -rk0 2>/dev/null || :
    clean_with_sudo /var/cache/pacman/pkg/*
  fi

  # APT cache (Debian)
  if has apt-get; then
    run_priv apt-get clean -yq 2>/dev/null || :
    run_priv apt-get autoclean -yq 2>/dev/null || :
    run_priv apt-get autoremove --purge -yq 2>/dev/null || :
  fi

  # Yay cache
  if has yay; then
    clean_paths ~/.cache/yay/*
  fi

  # Paru cache
  if has paru; then
    clean_paths ~/.cache/paru/*
  fi

  # Flatpak cache
  if has flatpak; then
    run_priv flatpak uninstall --unused -y 2>/dev/null || :
    clean_paths ~/.var/app/*/cache/*
  fi

  # Snap cache
  if has snap; then
    run_priv snap refresh 2>/dev/null || :
    LANG=C snap list --all | awk '/disabled/{system("sudo snap remove " $1 " --revision=" $3)}' 2>/dev/null || :
  fi
}

# Clean language-specific package manager caches
clean_language_caches() {
  info "Cleaning language-specific caches"

  # npm cache
  if has npm; then
    npm cache clean --force 2>/dev/null || :
    clean_paths ~/.npm/_cacache/*
  fi

  # Yarn cache
  if has yarn; then
    yarn cache clean 2>/dev/null || :
  fi

  # pip cache
  if has pip; then
    pip cache purge 2>/dev/null || :
  fi
  if has pip3; then
    pip3 cache purge 2>/dev/null || :
  fi
  clean_paths ~/.cache/pip/*

  # Cargo cache
  if has cargo; then
    cargo cache --autoclean 2>/dev/null || :
    clean_paths ~/.cargo/registry/cache/* ~/.cargo/registry/src/*
    [[ -d ~/.cargo/registry ]] && \
      find ~/.cargo/registry -type f -name "*.crate" -delete 2>/dev/null || :
  fi

  # Go cache
  if has go; then
    go clean -cache -modcache 2>/dev/null || :
  fi

  # Composer cache
  if has composer; then
    composer clear-cache 2>/dev/null || :
  fi
}

# ============================================================================
# Container Cleanup
# ============================================================================

# Clean Docker resources
# Removes unused Docker containers, images, volumes, and build cache
clean_docker() {
  if ! has docker; then
    return 0
  fi

  info "Cleaning Docker resources"

  run_priv docker system prune -af --volumes 2>/dev/null || :
  run_priv docker container prune -f 2>/dev/null || :
  run_priv docker image prune -af 2>/dev/null || :
  run_priv docker volume prune -f 2>/dev/null || :
  run_priv docker builder prune -af 2>/dev/null || :
}

# Clean Podman resources
# Removes unused Podman containers, images, and volumes
clean_podman() {
  if ! has podman; then
    return 0
  fi

  info "Cleaning Podman resources"

  podman system prune -af --volumes 2>/dev/null || :
  podman container prune -f 2>/dev/null || :
  podman image prune -af 2>/dev/null || :
  podman volume prune -f 2>/dev/null || :
}

# ============================================================================
# Browser Cache Cleanup
# ============================================================================

# Clean Firefox-family browser cache
# Usage: clean_firefox_cache "firefox" "$HOME/.mozilla/firefox"
clean_firefox_cache() {
  local browser_name=$1 base_dir=$2

  [[ -d $base_dir ]] || return 0

  info "Cleaning ${browser_name} cache"

  # Source arch.sh if available for profile detection
  if [[ -n ${_ARCH_LIB_LOADED:-} ]]; then
    # Use library functions if available
    local profile
    while IFS= read -r profile; do
      clean_paths \
        "$profile/cache2" \
        "$profile/startupCache" \
        "$profile/OfflineCache" \
        "$profile/shader-cache"
    done < <(mozilla_profiles "$base_dir")
  else
    # Fallback: clean all profile directories
    clean_paths \
      "$base_dir"/*/cache2 \
      "$base_dir"/*/startupCache \
      "$base_dir"/*/OfflineCache \
      "$base_dir"/*/shader-cache
  fi
}

# Clean Chromium-family browser cache
# Usage: clean_chromium_cache "chromium" "$HOME/.config/chromium"
clean_chromium_cache() {
  local browser_name=$1 base_dir=$2

  [[ -d $base_dir ]] || return 0

  info "Cleaning ${browser_name} cache"

  # Source arch.sh if available for profile detection
  if [[ -n ${_ARCH_LIB_LOADED:-} ]]; then
    # Use library functions if available
    local root profile
    while IFS= read -r root; do
      while IFS= read -r profile; do
        clean_paths \
          "$profile/Cache" \
          "$profile/Code Cache" \
          "$profile/GPUCache" \
          "$profile/Service Worker/CacheStorage" \
          "$profile/Service Worker/ScriptCache"
      done < <(chrome_profiles "$root")
    done < <(chrome_roots_for "$browser_name")
  else
    # Fallback: clean common directories
    clean_paths \
      "$base_dir"/Default/Cache \
      "$base_dir"/Default/"Code Cache" \
      "$base_dir"/Default/GPUCache \
      "$base_dir"/Profile\ */Cache \
      "$base_dir"/Profile\ */"Code Cache" \
      "$base_dir"/Profile\ */GPUCache
  fi
}

# Clean all browser caches
clean_all_browsers() {
  info "Cleaning browser caches"

  # Firefox family
  clean_firefox_cache "Firefox" "$HOME/.mozilla/firefox"
  clean_firefox_cache "LibreWolf" "$HOME/.librewolf"
  clean_firefox_cache "Floorp" "$HOME/.floorp"
  clean_firefox_cache "Waterfox" "$HOME/.waterfox"

  # Chromium family
  clean_chromium_cache "chromium" "$HOME/.config/chromium"
  clean_chromium_cache "chrome" "$HOME/.config/google-chrome"
  clean_chromium_cache "brave" "$HOME/.config/BraveSoftware/Brave-Browser"

  # Electron apps
  clean_paths \
    ~/.config/Code/Cache \
    ~/.config/Code/CachedData \
    ~/.config/discord/Cache \
    ~/.config/Slack/Cache \
    ~/.var/app/com.visualstudio.code/cache
}

# Ensure browsers are not running before cleaning
# Usage: ensure_browsers_closed "firefox" "chromium" "brave"
ensure_browsers_closed() {
  local -a browsers=(
    firefox firefox-esr librewolf floorp waterfox
    chromium google-chrome chrome brave opera
    discord slack code
  )

  # Add custom browsers from arguments
  [[ $# -gt 0 ]] && browsers+=("$@")

  # Check if arch.sh is loaded for ensure_not_running_any
  if [[ -n ${_ARCH_LIB_LOADED:-} ]]; then
    ensure_not_running_any "${browsers[@]}"
  else
    # Fallback: simple pkill
    for browser in "${browsers[@]}"; do
      if pgrep -x "$browser" &>/dev/null; then
        warn "Killing ${browser}..."
        pkill -TERM -x "$browser" &>/dev/null || :
      fi
    done
    sleep 2
  fi
}

# ============================================================================
# SQLite Optimization
# ============================================================================

# Vacuum all SQLite databases in a directory
# Usage: vacuum_sqlite_in_dir "$HOME/.mozilla/firefox/profile"
vacuum_sqlite_in_dir() {
  local dir=$1 total=0 db saved

  [[ -d $dir ]] || return 0

  info "Vacuuming SQLite databases in: $dir"

  # Requires arch.sh for vacuum_sqlite function
  if [[ -n ${_ARCH_LIB_LOADED:-} ]]; then
    while IFS= read -r -d '' db; do
      [[ -f $db ]] || continue
      saved=$(vacuum_sqlite "$db" || printf '0')
      ((saved > 0)) && total=$((total + saved))
    done < <(find0 "$dir" -maxdepth 3 -type f -name "*.sqlite")

    ((total > 0)) && ok "Vacuumed SQLite DBs, saved $((total / 1024)) KB"
  fi
}

# Vacuum SQLite databases in browser profiles
vacuum_browser_sqlite() {
  info "Vacuuming browser SQLite databases"

  vacuum_sqlite_in_dir "$HOME/.mozilla/firefox"
  vacuum_sqlite_in_dir "$HOME/.librewolf"
  vacuum_sqlite_in_dir "$HOME/.config/chromium"
  vacuum_sqlite_in_dir "$HOME/.config/google-chrome"
  vacuum_sqlite_in_dir "$HOME/.config/BraveSoftware"
}

# ============================================================================
# Aggregated Cleanup Functions
# ============================================================================

# Run basic cleaning (safe for all systems)
clean_all_basic() {
  section "Running Basic Cleanup"

  clean_cache_dirs
  clean_trash
  clean_history_files
  clean_crash_dumps
  clean_journal_logs
  clean_package_caches
}

# Run comprehensive cleanup (includes optional services)
clean_all_comprehensive() {
  section "Running Comprehensive Cleanup"

  clean_cache_dirs
  clean_trash
  clean_history_files
  clean_crash_dumps
  clean_journal_logs
  clean_package_caches
  clean_language_caches
  clean_docker
  clean_podman
  clean_all_browsers
  vacuum_browser_sqlite
}

# Deep clean (aggressive cleanup)
clean_all_deep() {
  section "Running Deep Cleanup"

  # Close browsers first
  ensure_browsers_closed

  # Run comprehensive cleanup
  clean_all_comprehensive

  # Additional deep cleaning
  info "Performing deep system cleanup"

  # Clean old kernels (Debian)
  if has apt-get; then
    run_priv apt-get autoremove --purge -y 2>/dev/null || :
  fi

  # Clean orphaned packages (Arch)
  if has pacman; then
    local orphans
    orphans=$(pacman -Qtdq 2>/dev/null) || orphans=""
    if [[ -n $orphans ]]; then
      echo "$orphans" | run_priv pacman -Rns - --noconfirm 2>/dev/null || :
    fi
  fi

  # Clean rotated logs
  clean_with_sudo /var/log/*.gz /var/log/*.[0-9] /var/log/*.old
}

# ============================================================================
# Selective Cleanup Functions
# ============================================================================

# Clean only user-space data (no sudo required)
clean_user_only() {
  section "Cleaning User Space"

  clean_paths \
    ~/.cache/* \
    ~/.thumbnails/* \
    ~/.local/share/Trash/*

  clean_package_caches
  clean_all_browsers
}

# Clean only system-space data (requires sudo)
clean_system_only() {
  section "Cleaning System Space"

  require_root || die "System cleanup requires root privileges"

  clean_journal_logs
  clean_crash_dumps
  clean_with_sudo /tmp/* /var/tmp/* /var/cache/*
  clean_docker
  clean_podman
}

# ============================================================================
# Library Load Confirmation
# ============================================================================

_CLEANING_LIB_LOADED=1
return 0
