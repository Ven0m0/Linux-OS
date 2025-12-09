#!/usr/bin/env bash
# Enhanced system cleaning with privacy configuration
# Refactored version with improved structure and maintainability

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/browser-utils.sh"
source "$SCRIPT_DIR/../lib/pkg-utils.sh"

# Initialize shell with strict settings
init_shell
export HOME="${HOME:-/home/${SUDO_USER:-$USER}}"

# Capture current disk usage
capture_disk_usage(){
  df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}'
}

#============ Configuration ============
declare -r MAX_PARALLEL_JOBS="$(nproc 2>/dev/null || echo 4)"
declare -r SQLITE_TIMEOUT=30

configure_firefox_privacy(){
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
      existing_prefs=$(< "$prefs_file" 2>/dev/null) || existing_prefs=""
      for pref in "${firefox_prefs[@]}"; do
        [[ $existing_prefs == *"$pref"* ]] || {
          printf '%s\n' "$pref">> "$prefs_file"
          ((prefs_changed++))
        }
      done
    done < <(find "$dir" -maxdepth 1 -type d \( -name "*.default*" -o -name "default-*" \))
  done
  ((prefs_changed> 0)) && printf '  %s %d prefs\n' "${GRN}Firefox privacy:" "$prefs_changed${DEF}"
}

configure_python_history(){
  local history_file="${HOME}/.python_history"
  [[ -f $history_file ]] || touch "$history_file"
  sudo chattr +i "$history_file" &>/dev/null && printf '  %s\n' "${GRN}Python history locked${DEF}" || :
}

#============ Banner ============
banner(){
  printf '%s\n' "${LBLU} ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ ${DEF}"
  printf '%s\n' "${PNK}██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ ${DEF}"
  printf '%s\n' "${BWHT}██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗${DEF}"
  printf '%s\n' "${PNK}██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║${DEF}"
  printf '%s\n' "${LBLU}╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝${DEF}"
  printf '%s\n' "${LBLU} ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ${DEF}"
}

#============ Cleaning Functions ============
clean_browsers(){
  printf '%s\n' "🔄${BLU}Cleaning browsers...${DEF}"

  # Clean Mozilla-based browsers
  ensure_not_running firefox librewolf floorp waterfox palemoon conkeror
  while IFS= read -r base; do
    # Special handling for Waterfox nested structure
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
  done < <(mozilla_bases_for "$USER")

  # Clean Mozilla cache directories
  rm -rf "${HOME}/.cache/mozilla"/* "${HOME}/.var/app/org.mozilla.firefox/cache"/* \
    "${HOME}/snap/firefox/common/.cache"/* &>/dev/null || :

  # Clean Chromium-based browsers
  ensure_not_running google-chrome chromium brave-browser brave opera vivaldi midori qupzilla
  while IFS= read -r root; do
    rm -rf "$root"/{GraphiteDawnCache,ShaderCache,*_crx_cache} &>/dev/null || :
    while IFS= read -r profdir; do
      [[ -d $profdir ]] || continue
      (cd "$profdir" && clean_sqlite_dbs)
      rm -rf "$profdir"/{Cache,GPUCache,"Code Cache","Service Worker",Logs} &>/dev/null || :
    done < <(chrome_profiles "$root")
  done < <(chrome_roots_for "$USER")
}

clean_mail_clients(){
  printf '%s\n' "📧${BLU}Cleaning mail clients...${DEF}"
  ensure_not_running thunderbird icedove
  while IFS= read -r base; do
    while IFS= read -r prof; do
      [[ -d $prof ]] && (cd "$prof" && clean_sqlite_dbs)
    done < <(mozilla_profiles "$base")
  done < <(mail_bases_for "$USER")
}

clean_electron(){
  local -a apps=("Code" "VSCodium" "Microsoft/Microsoft Teams")
  for app in "${apps[@]}"; do
    local d="${HOME}/.config/$app"
    [[ -d $d ]] || continue
    rm -rf "$d"/{Cache,GPUCache,"Code Cache",logs,Crashpad} &>/dev/null || :
  done
}

privacy_clean(){
  printf '%s\n' "🔒${MGN}Privacy cleanup...${DEF}"
  rm -f "${HOME}/.bash_history" "${HOME}/.zsh_history" "${HOME}/.python_history" "${HOME}/.history" \
    "${HOME}/.local/share/fish/fish_history" &>/dev/null || :
  sudo rm -f /root/.bash_history /root/.zsh_history /root/.python_history /root/.history &>/dev/null || :
  rm -rf "${HOME}/.thumbnails"/* "${HOME}/.cache/thumbnails"/* &>/dev/null || :
  rm -f "${HOME}/.recently-used.xbel" "${HOME}/.local/share/recently-used.xbel"* &>/dev/null || :
}

privacy_config(){
  printf '%s\n' "🔒${MGN}Privacy configuration...${DEF}"
  configure_firefox_privacy
  configure_python_history
}

pkg_cache_clean(){
  pkg_clean
}

snap_flatpak_trim(){
  has flatpak && flatpak uninstall --unused --delete-data -y &>/dev/null || :
  if has snap; then
    printf '%s\n' "🔄${BLU}Removing old Snap revisions...${DEF}"
    while read -r name version rev tracking publisher notes; do
      [[ ${notes:-} == *disabled* ]] && sudo snap remove "$name" --revision "$rev" &>/dev/null || :
    done < <(snap list --all 2>/dev/null || :)
    rm -rf "${HOME}/snap"/*/*/.cache/* &>/dev/null || :
  fi
  sudo rm -rf /var/lib/snapd/cache/* /var/tmp/flatpak-cache-* &>/dev/null || :
}

system_clean(){
  printf '%s\n' "🔄${BLU}System cleanup...${DEF}"
  sudo resolvectl flush-caches &>/dev/null || :
  sudo systemd-resolve --flush-caches &>/dev/null || :
  pkg_cache_clean
  sudo journalctl --rotate -q &>/dev/null || :
  sudo journalctl --vacuum-size=10M -q &>/dev/null || :
  sudo find /var/log -type f -name '*.old' -delete &>/dev/null || :
  sudo swapoff -a &>/dev/null || :
  sudo swapon -a &>/dev/null || :
  sudo systemd-tmpfiles --clean &>/dev/null || :
  rm -rf "${HOME}/.local/share/Trash"/* &>/dev/null || :
  rm -rf "${HOME}/.var/app"/*/cache/* &>/dev/null || :
  sudo rm -rf /tmp/* /var/tmp/* &>/dev/null || :
  has bleachbit && {
    bleachbit -c --preset &>/dev/null || :
    sudo bleachbit -c --preset &>/dev/null || :
  }
  sudo fstrim -a --quiet-unsupported &>/dev/null || :
  has fc-cache && sudo fc-cache -r &>/dev/null || :
  has localepurge && {
    localepurge &>/dev/null || :
    sudo localepurge &>/dev/null
  }
}

#============ Main ============
main(){
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
  printf '3' | sudo tee /proc/sys/vm/drop_caches &>/dev/null || :
  # Clean package managers
  has cargo-cache && {
    cargo cache -efg &>/dev/null || :
    cargo cache -ef trim --limit 1B &>/dev/null || :
  }
  has uv && uv clean -q &>/dev/null || :
  has bun && bun pm cache rm &>/dev/null || :
  has pnpm && {
    pnpm prune &>/dev/null || :
    pnpm store prune &>/dev/null || :
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
