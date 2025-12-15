#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
# Enhanced system cleaning with privacy configuration
# Refactored version with improved structure and maintainability
# Colors
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
export BLK RED GRN YLW BLU MGN CYN WHT LBLU PNK BWHT DEF BLD

# Core helper functions
has() { command -v -- "$1" &> /dev/null; }
xecho() { printf '%b\n' "$*"; }
# Capture current disk usage
capture_disk_usage() {
  df -h --output=used,pcent / 2> /dev/null | awk 'NR==2{print $1, $2}'
}
# Package manager detection (cached)
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()
detect_pkg_manager() {
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

get_pkg_manager() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager > /dev/null
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

# NUL-safe finder using fdf/fd/fdfind/find
find0() {
  local root="$1"
  shift
  if has fdf; then
    fdf -H -0 "$@" . "$root"
  elif has fd; then
    fd -H -0 "$@" . "$root"
  elif has fdfind; then
    fdfind -H -0 "$@" . "$root"
  else
    find "$root" "$@" -print0
  fi
}

# Browser helper functions
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

# List Default + Profile * dirs under a Chromium root
chrome_profiles() {
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do
    [[ -d $d ]] && printf '%s\n' "$d"
  done
}

#============ Configuration ============
declare -r MAX_PARALLEL_JOBS="$(nproc 2> /dev/null || echo 4)"
declare -r SQLITE_TIMEOUT=30

configure_firefox_privacy() {
  local prefs_changed=0
  local -a firefox_prefs=(
    'user_pref("browser.startup.homepage_override.mstone", "ignore");'
    'user_pref("browser.newtabpage.enabled", false);'
    'user_pref("browser.newtabpage.activity-stream.showSponsored", false);'
    'user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);'
    'user_pref("geo.enabled", false);'
    'user_pref("geo.provider.network.url", "");'
    'user_pref("browser.search.suggest.enabled", false);'
    'user_pref("network.dns.disablePrefetch", true);'
    'user_pref("network.prefetch-next", false);'
    'user_pref("network.predictor.enabled", false);'
    'user_pref("dom.battery.enabled", false);'
    'user_pref("privacy.resistFingerprinting", true);'
    'user_pref("privacy.trackingprotection.enabled", true);'
    'user_pref("privacy.trackingprotection.socialtracking.enabled", true);'
    'user_pref("beacon.enabled", false);'
  )
  local -a firefox_dirs=(
    ~/.mozilla/firefox
    ~/.var/app/org.mozilla.firefox/.mozilla/firefox
    ~/snap/firefox/common/.mozilla/firefox
  )
  for dir in "${firefox_dirs[@]}"; do
    [[ ! -d $dir ]] && continue
    while IFS= read -r profile; do
      local prefs_file="$profile/user.js"
      touch "$prefs_file"
      # Read existing prefs once instead of calling grep for each pref
      local existing_prefs
      existing_prefs=$(< "$prefs_file" 2> /dev/null) || existing_prefs=""
      for pref in "${firefox_prefs[@]}"; do
        [[ $existing_prefs == *"$pref"* ]] || {
          printf '%s\n' "$pref" >> "$prefs_file"
          ((prefs_changed++))
        }
      done
    done < <(find "$dir" -maxdepth 1 -type d \( -name "*.default*" -o -name "default-*" \))
  done
  ((prefs_changed > 0)) && printf '  %s %d prefs\n' "${GRN}Firefox privacy:" "$prefs_changed${DEF}"
}

configure_python_history() {
  local history_file="${HOME}/.python_history"
  [[ -f $history_file ]] || touch "$history_file"
  sudo chattr +i "$history_file" &> /dev/null && printf '  %s\n' "${GRN}Python history locked${DEF}" || :
}

#============ Banner ============
banner() {
  printf '%s\n' "${LBLU} ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ ${DEF}"
  printf '%s\n' "${PNK}██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ ${DEF}"
  printf '%s\n' "${BWHT}██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗${DEF}"
  printf '%s\n' "${PNK}██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║${DEF}"
  printf '%s\n' "${LBLU}╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝${DEF}"
  printf '%s\n' "${LBLU} ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ${DEF}"
}

#============ Cleaning Functions ============
clean_browsers() {
  printf '%s\n' "🔄${BLU}Cleaning browsers...${DEF}"
  local -a moz_bases=(
    "${HOME}/.mozilla/firefox"
    "${HOME}/.librewolf"
    "${HOME}/.floorp"
    "${HOME}/.waterfox"
    "${HOME}/.moonchild productions/pale moon"
    "${HOME}/.conkeror.mozdev.org/conkeror"
    "${HOME}/.var/app/org.mozilla.firefox/.mozilla/firefox"
    "${HOME}/.var/app/io.gitlab.librewolf-community/.mozilla/firefox"
    "${HOME}/.var/app/com.google.Chrome/.mozilla/firefox" # Added for Chrome Flatpak
    "${HOME}/snap/firefox/common/.mozilla/firefox"
  )
  ensure_not_running firefox librewolf floorp waterfox palemoon conkeror
  for base in "${moz_bases[@]}"; do
    [[ -d $base ]] || continue
    if [[ $base == "$HOME/.waterfox" ]]; then
      for b in "$base"/*; do
        [[ -d $b ]] || continue
        while IFS= read -r prof; do
          [[ -d $prof ]] && (cd "$prof" && clean_sqlite_dbs)
        done < <(mozilla_profiles "$b")
      done
    else
      while IFS= read -r prof; do
        [[ -d $prof ]] && (cd "$prof" && clean_sqlite_dbs)
      done < <(mozilla_profiles "$base")
    fi
  done
  rm -rf "${HOME}/.cache/mozilla"/* "${HOME}/.var/app/org.mozilla.firefox/cache"/* \
    "${HOME}/snap/firefox/common/.cache"/* &> /dev/null || :
  ensure_not_running google-chrome chromium brave-browser brave opera vivaldi midori qupzilla
  local -a chrome_dirs=(
    "${HOME}/.config/google-chrome"
    "${HOME}/.config/chromium"
    "${HOME}/.config/BraveSoftware/Brave-Browser"
    "${HOME}/.config/opera"
    "${HOME}/.config/vivaldi"
    "${HOME}/.config/midori"
    "${HOME}/.var/app/com.google.Chrome/config/google-chrome"
    "${HOME}/.var/app/org.chromium.Chromium/config/chromium"
    "${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
  )
  for root in "${chrome_dirs[@]}"; do
    [[ -d $root ]] || continue
    rm -rf "$root"/{GraphiteDawnCache,ShaderCache,*_crx_cache} &> /dev/null || :
    while IFS= read -r profdir; do
      [[ -d $profdir ]] || continue
      (cd "$profdir" && clean_sqlite_dbs)
      rm -rf "$profdir"/{Cache,GPUCache,"Code Cache","Service Worker",Logs} &> /dev/null || :
    done < <(chrome_profiles "$root")
  done
}

clean_mail_clients() {
  printf '%s\n' "📧${BLU}Cleaning mail clients...${DEF}"
  local -a mail_bases=(
    "${HOME}/.thunderbird"
    "${HOME}/.icedove"
    "${HOME}/.mozilla-thunderbird"
    "${HOME}/.var/app/org.mozilla.Thunderbird/.thunderbird"
  )
  ensure_not_running thunderbird icedove
  for base in "${mail_bases[@]}"; do
    [[ -d $base ]] || continue
    while IFS= read -r prof; do
      [[ -d $prof ]] && (cd "$prof" && clean_sqlite_dbs)
    done < <(mozilla_profiles "$base")
  done
}

clean_electron() {
  local -a apps=("Code" "VSCodium" "Microsoft/Microsoft Teams")
  for app in "${apps[@]}"; do
    local d="${HOME}/.config/$app"
    [[ -d $d ]] || continue
    rm -rf "$d"/{Cache,GPUCache,"Code Cache",logs,Crashpad} &> /dev/null || :
  done
}

privacy_clean() {
  printf '%s\n' "🔒${MGN}Privacy cleanup...${DEF}"
  rm -f "${HOME}/.bash_history" "${HOME}/.zsh_history" "${HOME}/.python_history" "${HOME}/.history" \
    "${HOME}/.local/share/fish/fish_history" &> /dev/null || :
  sudo rm -f /root/.bash_history /root/.zsh_history /root/.python_history /root/.history &> /dev/null || :
  rm -rf "${HOME}/.thumbnails"/* "${HOME}/.cache/thumbnails"/* &> /dev/null || :
  rm -f "${HOME}/.recently-used.xbel" "${HOME}/.local/share/recently-used.xbel"* &> /dev/null || :
}

privacy_config() {
  printf '%s\n' "🔒${MGN}Privacy configuration...${DEF}"
  configure_firefox_privacy
  configure_python_history
}

pkg_cache_clean() {
  if has pacman; then
    local pkgmgr=$(get_pkg_manager)
    sudo paccache -rk0 -q &> /dev/null || :
    sudo "$pkgmgr" -Scc --noconfirm &> /dev/null || :
    has paru && paru -Scc --noconfirm &> /dev/null || :
  fi
  has apt-get && {
    sudo apt-get clean -y &> /dev/null
    sudo apt-get autoclean &> /dev/null
  }
}

snap_flatpak_trim() {
  has flatpak && flatpak uninstall --unused --delete-data -y &> /dev/null || :
  if has snap; then
    printf '%s\n' "🔄${BLU}Removing old Snap revisions...${DEF}"
    while read -r name version rev tracking publisher notes; do
      [[ ${notes:-} == *disabled* ]] && sudo snap remove "$name" --revision "$rev" &> /dev/null || :
    done < <(snap list --all 2> /dev/null || :)
    rm -rf "${HOME}/snap"/*/*/.cache/* &> /dev/null || :
  fi
  sudo rm -rf /var/lib/snapd/cache/* /var/tmp/flatpak-cache-* &> /dev/null || :
}

system_clean() {
  printf '%s\n' "🔄${BLU}System cleanup...${DEF}"
  sudo resolvectl flush-caches &> /dev/null || :
  sudo systemd-resolve --flush-caches &> /dev/null || :
  pkg_cache_clean
  sudo journalctl --rotate -q &> /dev/null || :
  sudo journalctl --vacuum-size=10M -q &> /dev/null || :
  sudo find /var/log -type f -name '*.old' -delete &> /dev/null || :
  sudo swapoff -a &> /dev/null || :
  sudo swapon -a &> /dev/null || :
  sudo systemd-tmpfiles --clean &> /dev/null || :
  rm -rf "${HOME}/.local/share/Trash"/* &> /dev/null || :
  rm -rf "${HOME}/.var/app"/*/cache/* &> /dev/null || :
  sudo rm -rf /tmp/* /var/tmp/* &> /dev/null || :
  has bleachbit && {
    bleachbit -c --preset &> /dev/null || :
    sudo bleachbit -c --preset &> /dev/null || :
  }
  sudo fstrim -a --quiet-unsupported &> /dev/null || :
  has fc-cache && sudo fc-cache -r &> /dev/null || :
  has localepurge && {
    localepurge &> /dev/null || :
    sudo localepurge &> /dev/null
  }
}

#============ Main ============
main() {
  case ${1:-} in
    config)
      banner
      privacy_config
      printf '\n%s\n' "${GRN}Privacy configuration complete${DEF}"
      return
      ;;
  esac
  banner
  local disk_before disk_after
  disk_before=$(capture_disk_usage)
  sync
  printf '3' | sudo tee /proc/sys/vm/drop_caches &> /dev/null || :
  # Clean package managers
  has cargo-cache && {
    cargo cache -efg &> /dev/null || :
    cargo cache -ef trim --limit 1B &> /dev/null || :
  }
  has uv && uv clean -q &> /dev/null || :
  has bun && bun pm cache rm &> /dev/null || :
  has pnpm && {
    pnpm prune &> /dev/null || :
    pnpm store prune &> /dev/null || :
  }
  # Run cleaning functions
  clean_browsers
  clean_mail_clients
  clean_electron
  privacy_clean
  [[ ${1:-} == full ]] && privacy_config
  snap_flatpak_trim
  system_clean
  disk_after=$(capture_disk_usage)
  printf '\n%s\n' "${GRN}System cleaned${DEF}"
  printf '==> %s %s\n' "${BLU}Disk usage before:${DEF}" "$disk_before"
  printf '==> %s %s\n' "${GRN}Disk usage after:${DEF}" "$disk_after"
}
main "$@"
