#!/usr/bin/env bash
# Enhanced system cleaning with profile-cleaner integration
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C LANGUAGE=C HOME="/home/${SUDO_USER:-$USER}"

#============ Colors ============
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
BLU=$'\e[34m' GRN=$'\e[32m' YLW=$'\e[33m' MGN=$'\e[35m' DEF=$'\e[0m'
#============ Helper Functions ============
has(){ command -v -- "$1" &>/dev/null; }
get_pkg_manager(){
  if has paru; then
    printf 'paru'
  elif has yay; then
    printf 'yay'
  else
    printf 'pacman'
  fi
}
capture_disk_usage(){ df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}'; }
# Enhanced SQLite vacuum with reporting
vacuum_sqlite(){
  local db=$1 s_old s_new saved
  [[ -f $db ]] || return 0
  [[ -f ${db}-wal || -f ${db}-journal ]] && return 0
  head -c 16 "$db" 2>/dev/null | grep -qF 'SQLite format 3' || return 0
  s_old=$(stat -c%s "$db" 2>/dev/null) || return 0
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; REINDEX; PRAGMA optimize;' &>/dev/null || return 0
  s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
  saved=$((s_old - s_new))
  ((saved > 0)) && printf '%d\n' "$saved"
}

# Process SQLite databases with parallel processing
clean_sqlite_dbs(){
  local total=0 saved db_list=() count=0
  while IFS= read -r -d '' db; do
    [[ -f $db ]] && db_list+=("$db")
  done < <(find . -maxdepth 2 -type f -name '*.sqlite*' -print0 2>/dev/null)
  [[ ${#db_list[@]} -eq 0 ]] && return 0
  if has parallel; then
    while IFS= read -r line; do
      [[ $line =~ ^[0-9]+$ ]] && { total=$((total + line)); ((count++)); }
    done < <(printf '%s\n' "${db_list[@]}" | parallel -j"$(nproc)" vacuum_sqlite)
  elif has rust-parallel; then
    while IFS= read -r line; do
      [[ $line =~ ^[0-9]+$ ]] && { total=$((total + line)); ((count++)); }
    done < <(printf '%s\n' "${db_list[@]}" | rust-parallel vacuum_sqlite)
  else
    for db in "${db_list[@]}"; do
      saved=$(vacuum_sqlite "$db" 2>/dev/null)
      [[ $saved =~ ^[0-9]+$ ]] && { total=$((total + saved)); ((count++)); }
    done
  fi
  ((total > 0)) && printf '  %s %s (%d files)\n' "${GRN}Vacuumed:" "$((total / 1024)) KB${DEF}" "$count"
}

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

# Mozilla profile discovery with IsRelative support
mozilla_profiles(){
  local base=$1 p is_rel path_val
  [[ -d $base ]] || return 0
  if [[ -f $base/installs.ini ]]; then
    while IFS='=' read -r key val; do
      [[ $key == Default ]] && { path_val=$val; [[ -d $base/$path_val ]] && printf '%s\n' "$base/$path_val"; }
    done < <(grep -E '^Default=' "$base/installs.ini" 2>/dev/null)
  fi
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
          path_val='' is_rel=1 ;;
      esac
    done < <(grep -E '^(IsRelative|Path)=' "$base/profiles.ini" 2>/dev/null)
  fi
}
chrome_profiles(){
  local root="$1"
  for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s\n' "$d"; done
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
  local moz_bases=(
    "${HOME}/.mozilla/firefox"
    "${HOME}/.librewolf"
    "${HOME}/.floorp"
    "${HOME}/.waterfox"
    "${HOME}/.moonchild productions/pale moon"
    "${HOME}/.conkeror.mozdev.org/conkeror"
    "${HOME}/.var/app/org.mozilla.firefox/.mozilla/firefox"
    "${HOME}/.var/app/io.gitlab.librewolf-community/.mozilla/firefox"
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
  rm -rf "$HOME/.cache/mozilla"/* "$HOME/.var/app/org.mozilla.firefox/cache"/* \
    "$HOME/snap/firefox/common/.cache"/* &>/dev/null || :
  ensure_not_running google-chrome chromium brave-browser brave opera vivaldi midori qupzilla
  local chrome_dirs=(
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
    rm -rf "$root"/{GraphiteDawnCache,ShaderCache,*_crx_cache} &>/dev/null || :
    while IFS= read -r profdir; do
      [[ -d $profdir ]] || continue
      (cd "$profdir" && clean_sqlite_dbs)
      rm -rf "$profdir"/{Cache,GPUCache,"Code Cache","Service Worker",Logs} &>/dev/null || :
    done < <(chrome_profiles "$root")
  done
}

clean_mail_clients(){
  printf '%s\n' "📧${BLU}Cleaning mail clients...${DEF}"
  local mail_bases=(
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

clean_electron(){
  local apps=("Code" "VSCodium" "Microsoft/Microsoft Teams")
  for app in "${apps[@]}"; do
    local d="${HOME}/.config/$app"
    [[ -d $d ]] || continue
    rm -rf "$d"/{Cache,GPUCache,"Code Cache",logs,Crashpad} &>/dev/null || :
  done
}

privacy_clean(){
  printf '%s\n' "🔒${MGN}Privacy cleanup...${DEF}"
  rm -f "${HOME}"/.{bash,zsh,python}_history "${HOME}/.history" \
    "${HOME}"/.local/share/fish/fish_history &>/dev/null || :
  sudo rm -f /root/.{bash,zsh,python}_history /root/.history &>/dev/null || :
  rm -rf "${HOME}"/.thumbnails/* "${HOME}"/.cache/thumbnails/* &>/dev/null || :
  rm -f "${HOME}"/.recently-used.xbel "${HOME}"/.local/share/recently-used.xbel* &>/dev/null || :
}

pkg_cache_clean(){
  if has pacman; then
    local pkgmgr=$(get_pkg_manager)
    sudo paccache -rk0 -q &>/dev/null || :
    sudo "$pkgmgr" -Scc --noconfirm &>/dev/null || :
    has paru && paru -Scc --noconfirm &>/dev/null || :
  fi
  has apt-get && { sudo apt-get clean -y &>/dev/null; sudo apt-get autoclean &>/dev/null; }
}

snap_flatpak_trim(){
  has flatpak && flatpak uninstall --unused --delete-data -y &>/dev/null || :
  if has snap; then
    printf '%s\n' "🔄${BLU}Removing old Snap revisions...${DEF}"
    while read -r name version rev tracking publisher notes; do
      [[ ${notes:-} == *disabled* ]] && sudo snap remove "$name" --revision "$rev" &>/dev/null || :
    done < <(snap list --all 2>/dev/null || :)
    rm -rf "${HOME}"/snap/*/*/.cache/* &>/dev/null || :
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
  has bleachbit && { bleachbit -c --preset &>/dev/null || :; sudo bleachbit -c --preset &>/dev/null || :; }
  sudo fstrim -a --quiet-unsupported &>/dev/null || :
  has fc-cache && sudo fc-cache -r &>/dev/null || :
  has localepurge && { localepurge &>/dev/null || :; sudo localepurge &>/dev/null; }
}

#============ Main ============
main(){
  banner; sync
  local disk_before=$(capture_disk_usage) disk_after
  echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null || :
  has cargo-cache && { cargo cache -efg &>/dev/null || :; cargo cache -ef trim --limit 1B &>/dev/null || :; }
  has uv && uv clean -q &>/dev/null || :
  has bun && bun pm cache rm &>/dev/null || :
  has pnpm && { pnpm prune &>/dev/null || :; pnpm store prune &>/dev/null || :; }
  clean_browsers
  clean_mail_clients
  clean_electron
  privacy_clean
  snap_flatpak_trim
  system_clean
  disk_after=$(capture_disk_usage)
  printf '\n%s\n' "${GRN}System cleaned${DEF}"
  printf '==> %s %s\n' "${BLU}Disk usage before:${DEF}" "$disk_before"
  printf '==> %s %s\n' "${GRN}Disk usage after:${DEF}" "$disk_after"
}
main "$@"
