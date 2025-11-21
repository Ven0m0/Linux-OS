#!/usr/bin/env bash
# Optimized system cleaning script for Arch-based systems
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# Export common locale settings
export LC_ALL=C LANG=C LANGUAGE=C

#============ Colors ============
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
BLU=$'\e[34m' GRN=$'\e[32m' YLW=$'\e[33m' MGN=$'\e[35m' DEF=$'\e[0m'

#============ Helper Functions ============
has(){ command -v "$1" &>/dev/null; }

# Detect privilege escalation tool
get_priv_cmd(){
  local cmd
  for cmd in sudo-rs sudo doas; do
    if has "$cmd"; then
      printf '%s' "$cmd"
      return 0
    fi
  done
  [[ $EUID -eq 0 ]] || { echo "No privilege tool found" >&2; exit 1; }
  printf ''
}

# Initialize privilege tool
init_priv(){
  local priv_cmd; priv_cmd=$(get_priv_cmd)
  [[ -n $priv_cmd && $EUID -ne 0 ]] && "$priv_cmd" -v
  printf '%s' "$priv_cmd"
}

# Run command with privilege
run_priv(){
  local priv_cmd="${PRIV_CMD:-}"
  [[ -z $priv_cmd ]] && priv_cmd=$(get_priv_cmd)
  if [[ $EUID -eq 0 || -z $priv_cmd ]]; then
    "$@"
  else
    "$priv_cmd" -- "$@"
  fi
}

# Get package manager
get_pkg_manager(){
  if has paru; then
    printf 'paru'
  elif has yay; then
    printf 'yay'
  else
    printf 'pacman'
  fi
}

# Disk usage capture
capture_disk_usage(){
  df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}'
}

# SQLite vacuum
vacuum_sqlite(){
  local db=$1 s_old s_new
  [[ -f $db ]] || return 0
  [[ -f ${db}-wal || -f ${db}-journal ]] && return 0
  head -c 16 "$db" 2>/dev/null | grep -q 'SQLite format 3' || return 0
  s_old=$(stat -c%s "$db" 2>/dev/null) || return 0
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || return 0
  s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
  ((s_old > s_new)) && echo "$((s_old - s_new))"
}

clean_sqlite_dbs(){
  local total=0 saved
  while IFS= read -r -d '' db; do
    [[ -f $db ]] || continue
    saved=$(vacuum_sqlite "$db" 2>/dev/null)
    ((saved > 0)) && total=$((total + saved))
  done < <(find . -maxdepth 1 -type f -print0 2>/dev/null)
  ((total > 0)) && printf '  %s\n' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"
}

# Wait for processes to exit
ensure_not_running(){
  local timeout=6 pattern
  pattern=$(printf '%s|' "$@")
  pattern=${pattern%|}

  pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return 0

  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &>/dev/null && printf '  %s\n' "${YLW}Waiting for ${p}...${DEF}"
  done

  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return 0
    sleep 1
  done

  pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :
}

# Mozilla profile discovery
mozilla_profiles(){
  local base=$1 p
  [[ -d $base ]] || return 0

  if [[ -f $base/installs.ini ]]; then
    while IFS= read -r p; do
      [[ -d $base/$p ]] && printf '%s\n' "$base/$p"
    done < <(awk -F= '/^Default=/ {print $2}' "$base/installs.ini")
  fi

  if [[ -f $base/profiles.ini ]]; then
    while IFS= read -r p; do
      [[ -d $base/$p ]] && printf '%s\n' "$base/$p"
    done < <(awk -F= '/^Path=/ {print $2}' "$base/profiles.ini")
  fi
}

# Chromium profile discovery
chrome_profiles(){
  local root=$1
  for d in "$root"/Default "$root"/"Profile "*; do
    [[ -d $d ]] && printf '%s\n' "$d"
  done
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

  # Firefox family
  local moz_bases=(
    "$HOME/.mozilla/firefox"
    "$HOME/.librewolf"
    "$HOME/.floorp"
    "$HOME/.waterfox"
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
    "$HOME/.var/app/io.gitlab.librewolf-community/.mozilla/firefox"
    "$HOME/snap/firefox/common/.mozilla/firefox"
  )

  ensure_not_running firefox librewolf floorp waterfox

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

  rm -rf "$HOME/.cache/mozilla"/* "$HOME/.var/app/org.mozilla.firefox/cache"/* \
    "$HOME/snap/firefox/common/.cache"/* &>/dev/null || :

  # Chromium family
  ensure_not_running google-chrome chromium brave-browser brave opera

  local chrome_dirs=(
    "$HOME/.config/google-chrome"
    "$HOME/.config/chromium"
    "$HOME/.config/BraveSoftware/Brave-Browser"
    "$HOME/.config/opera"
    "$HOME/.var/app/com.google.Chrome/config/google-chrome"
    "$HOME/.var/app/org.chromium.Chromium/config/chromium"
    "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
  )

  for root in "${chrome_dirs[@]}"; do
    [[ -d $root ]] || continue

    # Clean root caches
    rm -rf "$root"/{GraphiteDawnCache,ShaderCache,*_crx_cache} &>/dev/null || :

    # Clean profiles
    while IFS= read -r profdir; do
      [[ -d $profdir ]] || continue
      (cd "$profdir" && clean_sqlite_dbs)
      rm -rf "$profdir"/{Cache,GPUCache,"Code Cache","Service Worker",Logs} &>/dev/null || :
    done < <(chrome_profiles "$root")
  done
}

clean_electron(){
  local apps=("Code" "VSCodium" "Microsoft/Microsoft Teams")
  for app in "${apps[@]}"; do
    local d="$HOME/.config/$app"
    [[ -d $d ]] || continue
    rm -rf "$d"/{Cache,GPUCache,"Code Cache",logs,Crashpad} &>/dev/null || :
  done
}

privacy_clean(){
  printf '%s\n' "🔒${MGN}Privacy cleanup...${DEF}"

  # History files
  rm -f "$HOME"/.{bash,zsh,python}_history "$HOME"/.history \
    "$HOME"/.local/share/fish/fish_history &>/dev/null || :
  run_priv rm -f /root/.{bash,zsh,python}_history /root/.history &>/dev/null || :

  # Thumbnails and recent files
  rm -rf "$HOME"/.thumbnails/* "$HOME"/.cache/thumbnails/* &>/dev/null || :
  rm -f "$HOME"/.recently-used.xbel "$HOME"/.local/share/recently-used.xbel* &>/dev/null || :
}

pkg_cache_clean(){
  if has pacman; then
    local pkgmgr; pkgmgr=$(get_pkg_manager)
    run_priv paccache -rk0 -q &>/dev/null || :
    run_priv "$pkgmgr" -Scc --noconfirm &>/dev/null || :
  fi

  has apt-get && { run_priv apt-get clean &>/dev/null || :; run_priv apt-get autoclean &>/dev/null || :; }
}

snap_flatpak_trim(){
  has flatpak && flatpak uninstall --unused --delete-data -y &>/dev/null || :

  if has snap; then
    printf '%s\n' "🔄${BLU}Removing old Snap revisions...${DEF}"
    while read -r name version rev tracking publisher notes; do
      [[ ${notes:-} == *disabled* ]] && run_priv snap remove "$name" --revision "$rev" &>/dev/null || :
    done < <(snap list --all 2>/dev/null || :)
    rm -rf "$HOME"/snap/*/*/.cache/* &>/dev/null || :
  fi

  run_priv rm -rf /var/lib/snapd/cache/* /var/tmp/flatpak-cache-* &>/dev/null || :
}

system_clean(){
  printf '%s\n' "🔄${BLU}System cleanup...${DEF}"

  # DNS cache
  run_priv resolvectl flush-caches &>/dev/null || :
  run_priv systemd-resolve --flush-caches &>/dev/null || :

  # Package caches
  pkg_cache_clean

  # Journal
  run_priv journalctl --rotate -q &>/dev/null || :
  run_priv journalctl --vacuum-size=10M -q &>/dev/null || :
  run_priv find /var/log -type f -name '*.old' -delete &>/dev/null || :

  # Swap
  run_priv swapoff -a &>/dev/null || :
  run_priv swapon -a &>/dev/null || :

  # Temp files
  run_priv systemd-tmpfiles --clean &>/dev/null || :
  rm -rf "$HOME/.local/share/Trash"/* &>/dev/null || :
  rm -rf "$HOME/.var/app"/*/cache/* &>/dev/null || :
  run_priv rm -rf /tmp/* /var/tmp/* &>/dev/null || :

  # Bleachbit
  has bleachbit && { bleachbit -c --preset &>/dev/null || :; run_priv bleachbit -c --preset &>/dev/null || :; }

  # Trim
  run_priv fstrim -a --quiet-unsupported &>/dev/null || :

  # Font cache
  has fc-cache && run_priv fc-cache -r &>/dev/null || :
}

#============ Main ============
main(){
  banner

  # Initialize privilege
  PRIV_CMD=$(init_priv)
  [[ $EUID -ne 0 ]] && "$PRIV_CMD" -v || :

  # Capture before state
  local disk_before disk_after
  disk_before=$(capture_disk_usage)

  # Drop caches
  sync
  echo 3 | run_priv tee /proc/sys/vm/drop_caches &>/dev/null || :

  # Dev caches
  has cargo-cache && { cargo cache -efg &>/dev/null || :; cargo cache -ef trim --limit 1B &>/dev/null || :; }
  has uv && uv clean -q &>/dev/null || :
  has bun && bun pm cache rm &>/dev/null || :
  has pnpm && { pnpm prune &>/dev/null || :; pnpm store prune &>/dev/null || :; }

  # Main cleaning
  clean_browsers
  clean_electron
  privacy_clean
  snap_flatpak_trim
  system_clean

  # Capture after state
  disk_after=$(capture_disk_usage)

  printf '\n%s\n' "${GRN}System cleaned${DEF}"
  printf '==> %s %s\n' "${BLU}Disk usage before:${DEF}" "$disk_before"
  printf '==> %s %s\n' "${GRN}Disk usage after:${DEF}" "$disk_after"
}

main "$@"
