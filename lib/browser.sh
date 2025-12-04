#!/usr/bin/env bash
# Browser profile detection and management library
# This library provides functions for detecting and listing browser profiles
# Usage: source "${SCRIPT_DIR}/../lib/browser.sh" || exit 1

# Ensure core.sh is loaded for has() and other helpers
[[ -n ${SCRIPT_DIR:-} ]] || SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/core.sh" 2>/dev/null || {
  echo "Error: core.sh not found" >&2
  return 1
}

#============ Browser Profile Detection ============

# Firefox-family profile discovery
# Returns the default profile path for Firefox-based browsers
# Usage: foxdir <base_dir>
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
# Returns all profile paths found in installs.ini and profiles.ini
# Usage: mozilla_profiles <base_dir>
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

# Get Chromium-based browser root directories
# Returns possible root directories for the specified browser
# Usage: chrome_roots_for <browser_name>
# Supported browsers: chrome, chromium, brave, opera
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
    edge)
      printf '%s\n' \
        "$HOME/.config/microsoft-edge" \
        "$HOME/.var/app/com.microsoft.Edge/config/microsoft-edge"
      ;;
    vivaldi)
      printf '%s\n' \
        "$HOME/.config/vivaldi" \
        "$HOME/.var/app/com.vivaldi.Vivaldi/config/vivaldi"
      ;;
    *) : ;;
  esac
}

# List Default + Profile * directories under a Chromium root
# Returns all profile paths found under a Chromium-based browser root
# Usage: chrome_profiles <root_dir>
chrome_profiles() {
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do
    [[ -d $d ]] && printf '%s\n' "$d"
  done
}

# Get all Mozilla-based browser base directories
# Returns base directories for Firefox and Firefox-based browsers
# Usage: mozilla_bases
mozilla_bases() {
  local -a bases=(
    "${HOME}/.mozilla/firefox"
    "${HOME}/.librewolf"
    "${HOME}/.waterfox"
    "${HOME}/.floorp"
    "${HOME}/.zen"
    "${HOME}/.var/app/org.mozilla.firefox/.mozilla/firefox"
    "${HOME}/.var/app/io.gitlab.librewolf-community/.librewolf"
    "${HOME}/snap/firefox/common/.mozilla/firefox"
  )
  for base in "${bases[@]}"; do
    [[ -d $base ]] && printf '%s\n' "$base"
  done
}

# Get all Chromium-based browser names
# Returns list of supported Chromium-based browser names
# Usage: chromium_browsers
chromium_browsers() {
  printf '%s\n' chrome chromium brave opera edge vivaldi
}
