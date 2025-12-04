#!/usr/bin/env bash
# lib/browser.sh - Browser and SQLite maintenance shared library
# Provides: Mozilla/Chromium profile detection, SQLite vacuum, process helpers
# Requires: lib/core.sh
# shellcheck disable=SC2034
[[ -n ${_LIB_BROWSER_LOADED:-} ]] && return 0
_LIB_BROWSER_LOADED=1

# Source core library if not loaded
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=lib/core.sh
[[ -z ${_LIB_CORE_LOADED:-} ]] && source "${SCRIPT_DIR}/core.sh"

#============ SQLite Maintenance ============
# Vacuum a single SQLite database and return bytes saved
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
  # Use fixed-string grep (-F) for faster literal matching
  if ! head -c 16 "$db" 2> /dev/null | grep -qF -- 'SQLite format 3'; then
    printf '0\n'
    return
  fi
  s_old=$(stat -c%s "$db" 2> /dev/null) || {
    printf '0\n'
    return
  }
  # VACUUM already rebuilds indices, making REINDEX redundant
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &> /dev/null || {
    printf '0\n'
    return
  }
  s_new=$(stat -c%s "$db" 2> /dev/null) || s_new=$s_old
  printf '%d\n' "$((s_old - s_new))"
}

# Clean SQLite databases in current working directory
clean_sqlite_dbs() {
  local total=0 db saved
  while IFS= read -r -d '' db; do
    [[ -f $db ]] || continue
    saved=$(vacuum_sqlite "$db" || printf '0')
    ((saved > 0)) && total=$((total + saved))
  done < <(find0 . -maxdepth 2 -type f -name '*.sqlite*' -print0 2> /dev/null)
  ((total > 0)) && printf '  %s\n' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"
}

#============ Process Management ============
# Wait for processes to exit, kill if timeout
ensure_not_running() {
  local timeout=6 p
  local pattern=$(printf '%s|' "$@")
  pattern=${pattern%|}

  # Quick check if any processes are running
  pgrep -x -u "$USER" -f "$pattern" &> /dev/null || return 0

  # Show waiting message for found processes
  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &> /dev/null && printf '  %s\n' "${YLW}Waiting for ${p} to exit...${DEF}"
  done

  # Single wait loop checking all processes with one pgrep call
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &> /dev/null || return 0
    sleep 1
  done

  # Kill any remaining processes
  if pgrep -x -u "$USER" -f "$pattern" &> /dev/null; then
    printf '  %s\n' "${RED}Killing remaining processes...${DEF}"
    pkill -KILL -x -u "$USER" -f "$pattern" &> /dev/null || :
    sleep 1
  fi
}

# Alias for backwards compatibility
ensure_not_running_any() { ensure_not_running "$@"; }

#============ Firefox/Mozilla Profile Detection ============
# Firefox-family profile discovery (single default)
foxdir() {
  local base=$1 p
  [[ -d $base ]] || return 1
  if [[ -f $base/installs.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini")
    [[ -n $p && -d $base/$p ]] && {
      printf '%s\n' "$base/$p"
      return 0
    }
  fi
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
mozilla_profiles() {
  local base=$1 p is_rel path_val
  [[ -d $base ]] || return 0

  # Process installs.ini
  if [[ -f $base/installs.ini ]]; then
    while IFS='=' read -r key val; do
      [[ $key == Default ]] && {
        path_val=$val
        [[ -d $base/$path_val ]] && printf '%s\n' "$base/$path_val"
      }
    done < <(grep -E '^Default=' "$base/installs.ini" 2> /dev/null)
  fi

  # Process profiles.ini with IsRelative support
  if [[ -f $base/profiles.ini ]]; then
    is_rel=1 path_val=''
    while IFS='=' read -r key val; do
      case $key in
        IsRelative) is_rel=$val ;;
        Path)
          path_val="$val"
          if [[ $is_rel -eq 0 ]]; then
            [[ -d $path_val ]] && printf '%s\n' "$path_val"
          else
            [[ -d $base/$path_val ]] && printf '%s\n' "$base/$path_val"
          fi
          path_val='' is_rel=1
          ;;
      esac
    done < <(grep -E '^(IsRelative|Path)=' "$base/profiles.ini" 2> /dev/null)
  fi
}

#============ Chromium Profile Detection ============
# Chromium roots (native/flatpak/snap)
chrome_roots_for() {
  case "$1" in
    chrome) printf '%s\n' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;;
    chromium) printf '%s\n' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;;
    brave) printf '%s\n' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;;
    opera) printf '%s\n' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;;
    vivaldi) printf '%s\n' "$HOME/.config/vivaldi" "$HOME/.config/vivaldi-snapshot" ;;
    *) : ;;
  esac
}

# List Default + Profile * dirs under a Chromium root
chrome_profiles() {
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do
    [[ -d $d ]] && printf '%s\n' "$d"
  done
}

#============ Common Browser Path Lists ============
# Get Mozilla-based browser base directories
get_mozilla_bases() {
  local -a bases=(
    "$HOME/.mozilla/firefox"
    "$HOME/.librewolf"
    "$HOME/.floorp"
    "$HOME/.waterfox"
    "$HOME/.moonchild productions/pale moon"
    "$HOME/.conkeror.mozdev.org/conkeror"
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
    "$HOME/.var/app/io.gitlab.librewolf-community/.mozilla/firefox"
    "$HOME/snap/firefox/common/.mozilla/firefox"
  )
  printf '%s\n' "${bases[@]}"
}

# Get Chromium-based browser base directories
get_chrome_bases() {
  local -a bases=(
    "$HOME/.config/google-chrome"
    "$HOME/.config/chromium"
    "$HOME/.config/BraveSoftware/Brave-Browser"
    "$HOME/.config/opera"
    "$HOME/.config/vivaldi"
    "$HOME/.config/midori"
    "$HOME/.var/app/com.google.Chrome/config/google-chrome"
    "$HOME/.var/app/org.chromium.Chromium/config/chromium"
    "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
  )
  printf '%s\n' "${bases[@]}"
}

# Get mail client base directories (Mozilla-based)
get_mail_bases() {
  local -a bases=(
    "$HOME/.thunderbird"
    "$HOME/.icedove"
    "$HOME/.mozilla-thunderbird"
    "$HOME/.var/app/org.mozilla.Thunderbird/.thunderbird"
  )
  printf '%s\n' "${bases[@]}"
}
