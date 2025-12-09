#!/usr/bin/env bash
# Browser and SQLite utility functions for Linux-OS scripts
# Source this file: source "${BASH_SOURCE%/*}/../lib/browser-utils.sh"

# Prevent multiple sourcing
[[ -n ${LINUX_OS_BROWSER_UTILS_LOADED:-} ]] && return 0
readonly LINUX_OS_BROWSER_UTILS_LOADED=1

# Ensure common.sh is loaded for helper functions
if [[ -z ${LINUX_OS_COMMON_LOADED:-} ]]; then
  source "${BASH_SOURCE%/*}/common.sh"
fi

# ============================================================================
# SQLITE DATABASE OPTIMIZATION
# ============================================================================

# Vacuum a single SQLite database and return bytes saved
# Usage: saved=$(vacuum_sqlite /path/to/db.sqlite)
vacuum_sqlite() {
  local db=${1:?} s_old s_new

  [[ -f $db ]] || {
    printf '0\n'
    return
  }

  # Skip if probably open (has WAL or journal file)
  [[ -f ${db}-wal || -f ${db}-journal ]] && {
    printf '0\n'
    return
  }

  # Validate it's actually a SQLite database file
  if ! head -c 16 "$db" 2>/dev/null | grep -qF -- 'SQLite format 3'; then
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
# Usage: (cd /path/to/profile && clean_sqlite_dbs)
clean_sqlite_dbs() {
  local total=0 db saved

  while IFS= read -r -d '' db; do
    [[ -f $db ]] || continue
    saved=$(vacuum_sqlite "$db" || printf '0')
    ((saved > 0)) && total=$((total + saved))
  done < <(find . -maxdepth 2 -type f -name '*.sqlite*' -print0 2>/dev/null)

  if ((total > 0)); then
    printf '  %s\n' "${GRN:-}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF:-}"
  fi
}

# ============================================================================
# PROCESS MANAGEMENT
# ============================================================================

# Wait for processes to exit, kill if timeout
# Usage: ensure_not_running firefox chromium brave
ensure_not_running() {
  local timeout=6 p
  local pattern=$(printf '%s|' "$@")
  pattern=${pattern%|}

  # Quick check if any processes are running
  pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return 0

  # Show waiting message for found processes
  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &>/dev/null \
      && printf '  %s\n' "${YLW:-}Waiting for ${p} to exit...${DEF:-}"
  done

  # Single wait loop checking all processes with one pgrep call
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return 0
    sleep 1
  done

  # Kill any remaining processes
  if pgrep -x -u "$USER" -f "$pattern" &>/dev/null; then
    printf '  %s\n' "${RED:-}Killing remaining processes...${DEF:-}"
    pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :
    sleep 1
  fi
}

# ============================================================================
# FIREFOX/MOZILLA PROFILE DISCOVERY
# ============================================================================

# Find default Firefox-family profile directory
# Usage: profile=$(foxdir ~/.mozilla/firefox)
foxdir() {
  local base=${1:?}
  local p

  [[ -d $base ]] || return 1

  # Try installs.ini first
  if [[ -f $base/installs.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini")
    [[ -n $p && -d $base/$p ]] && {
      printf '%s\n' "$base/$p"
      return 0
    }
  fi

  # Fallback to profiles.ini
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
# Handles both installs.ini and profiles.ini with IsRelative flag
# Usage: while read -r profile; do ...; done < <(mozilla_profiles ~/.mozilla/firefox)
mozilla_profiles() {
  local base=${1:?}
  local p is_rel path_val

  [[ -d $base ]] || return 0

  # Process installs.ini
  if [[ -f $base/installs.ini ]]; then
    while IFS='=' read -r key val; do
      [[ $key == Default ]] && {
        path_val=$val
        [[ -d $base/$path_val ]] && printf '%s\n' "$base/$path_val"
      }
    done < <(grep -E '^Default=' "$base/installs.ini" 2>/dev/null)
  fi

  # Process profiles.ini with IsRelative support
  if [[ -f $base/profiles.ini ]]; then
    is_rel=1
    path_val=''
    while IFS='=' read -r key val; do
      case $key in
        IsRelative)
          is_rel=$val
          ;;
        Path)
          path_val="$val"
          if [[ $is_rel -eq 0 ]]; then
            [[ -d $path_val ]] && printf '%s\n' "$path_val"
          else
            [[ -d $base/$path_val ]] && printf '%s\n' "$base/$path_val"
          fi
          path_val=''
          is_rel=1
          ;;
      esac
    done < <(grep -E '^(IsRelative|Path)=' "$base/profiles.ini" 2>/dev/null)
  fi
}

# ============================================================================
# CHROMIUM/CHROME PROFILE DISCOVERY
# ============================================================================

# List Default + Profile * dirs under a Chromium root
# Usage: while read -r profile; do ...; done < <(chrome_profiles ~/.config/google-chrome)
chrome_profiles() {
  local root=${1:?}
  local d

  for d in "$root"/Default "$root"/"Profile "*; do
    [[ -d $d ]] && printf '%s\n' "$d"
  done
}

# List common Chrome-based browser root directories
# Usage: while read -r root; do ...; done < <(chrome_roots_for "$USER")
chrome_roots_for() {
  local user=${1:-$USER}
  local home

  if [[ $user == root ]]; then
    home=/root
  else
    home="/home/$user"
  fi

  local -a roots=(
    "$home/.config/google-chrome"
    "$home/.config/chromium"
    "$home/.config/BraveSoftware/Brave-Browser"
    "$home/.config/opera"
    "$home/.config/vivaldi"
    "$home/.config/midori"
    "$home/.var/app/com.google.Chrome/config/google-chrome"
    "$home/.var/app/org.chromium.Chromium/config/chromium"
    "$home/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
  )

  for root in "${roots[@]}"; do
    [[ -d $root ]] && printf '%s\n' "$root"
  done
}

# ============================================================================
# COMMON BROWSER DIRECTORIES
# ============================================================================

# List common Mozilla-based browser base directories
# Usage: while read -r base; do ...; done < <(mozilla_bases_for "$USER")
mozilla_bases_for() {
  local user=${1:-$USER}
  local home

  if [[ $user == root ]]; then
    home=/root
  else
    home="/home/$user"
  fi

  local -a bases=(
    "$home/.mozilla/firefox"
    "$home/.librewolf"
    "$home/.floorp"
    "$home/.waterfox"
    "$home/.moonchild productions/pale moon"
    "$home/.conkeror.mozdev.org/conkeror"
    "$home/.var/app/org.mozilla.firefox/.mozilla/firefox"
    "$home/.var/app/io.gitlab.librewolf-community/.mozilla/firefox"
    "$home/snap/firefox/common/.mozilla/firefox"
  )

  for base in "${bases[@]}"; do
    [[ -d $base ]] && printf '%s\n' "$base"
  done
}

# List common Thunderbird/mail client base directories
# Usage: while read -r base; do ...; done < <(mail_bases_for "$USER")
mail_bases_for() {
  local user=${1:-$USER}
  local home

  if [[ $user == root ]]; then
    home=/root
  else
    home="/home/$user"
  fi

  local -a bases=(
    "$home/.thunderbird"
    "$home/.icedove"
    "$home/.mozilla-thunderbird"
    "$home/.var/app/org.mozilla.Thunderbird/.thunderbird"
  )

  for base in "${bases[@]}"; do
    [[ -d $base ]] && printf '%s\n' "$base"
  done
}

# ============================================================================
# RETURN SUCCESS
# ============================================================================

return 0
