#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar extglob
IFS=$'\n\t' SHELL=bash; export LC_ALL=C LANG=C LANGUAGE=C
#============ Color & Effects ============
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
has(){ command -v "$1" &>/dev/null; }
xecho(){ printf '%b\n' "$*"; }

#============ Banner ==========
print_banner(){
  local banner flag_colors; banner=$(
    cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ 
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ 
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
  )
  mapfile -t lines <<<"$banner"
  flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")
  local line_count=${#lines[@]} segments=${#flag_colors[@]}
  if ((line_count <= 1)); then
    for line in "${lines[@]}"; do printf '%s%s%s\n' "${flag_colors[0]}" "$line" "$DEF"; done
  else
    for i in "${!lines[@]}"; do
      local segment_index=$((i * (segments - 1) / (line_count - 1)))
      ((segment_index >= segments)) && segment_index=$((segments - 1))
      printf '%s%s%s\n' "${flag_colors[segment_index]}" "${lines[i]}" "$DEF"
    done
  fi
}
cleanup(){ :; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

capture_disk_usage(){
  local -n ref="$1"
  ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}

ensure_not_running(){
  local process_name=$1 timeout=6
  if pgrep -x -u "$USER" "$process_name" &>/dev/null; then
    xecho "  ${YLW}Waiting for ${process_name} to exit...${DEF}"
    while ((timeout-- > 0)) && pgrep -x -u "$USER" "$process_name" &>/dev/null; do
      sleep 1
    done
    if pgrep -x -u "$USER" "$process_name" &>/dev/null; then
      xecho "  ${RED}Killing ${process_name}...${DEF}"
      pkill -KILL -x -u "$USER" "$process_name" &>/dev/null || :
      sleep 1
    fi
  fi
}

clean_sqlite_dbs(){
  local db diff s_old s_new total_saved=0
  while read -r db; do
    s_old=$(stat -c%s "$db" 2>/dev/null) || continue
    sqlite3 "$db" "VACUUM; REINDEX;" &>/dev/null || continue
    s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
    diff=$((s_old - s_new)); total_saved=$((total_saved + diff))
  done < <(find . -maxdepth 1 -type f -print0 | xargs -0 file -e ascii | sed -n 's/:.*SQLite.*//p')
  if ((total_saved > 0)); then
    xecho "${GRN}Vacuumed SQLite DBs, saved $((total_saved / 1024)) KB${DEF}"
  fi
}
clean_browsers(){
  xecho "🔄${BLU}Cleaning browser data...${DEF}"
  # Firefox, Icecat, Seamonkey
  local ff_base="${HOME}/.mozilla"
  local browser
  for browser in firefox icecat seamonkey; do
    ensure_not_running "$browser"
    local profiles_ini="${ff_base}/${browser}/profiles.ini"
    if [[ -f "$profiles_ini" ]]; then
      xecho "  ${CYN}Cleaning ${browser} profiles...${DEF}"
      while read -r path; do
        local profile_dir="${ff_base}/${browser}/${path}"
        if [[ -d "$profile_dir" ]]; then
          (cd "$profile_dir" && clean_sqlite_dbs)
          rm -rf -- "${profile_dir}/"{bookmarkbackups,crashes,datareporting,minidumps,saved-telemetry-pings,sessionstore-*} &>/dev/null
        fi
      done < <(grep '^Path=' "$profiles_ini" | cut -d= -f2)
    fi
  done
  rm -rf -- "${HOME}/.cache/mozilla/"* &>/dev/null
  # Chromium, Chrome, etc.
  local chrome_base="${HOME}/.config"
  local chrome_browsers=(chromium chromium-beta chromium-dev
    google-chrome google-chrome-beta google-chrome-unstable
    brave-browser brave-browser-beta brave-browser-nightly)
  for browser in "${chrome_browsers[@]}"; do
    ensure_not_running "$browser"
    local browser_config_dir="${chrome_base}/${browser}"
    if [[ -d "$browser_config_dir" ]]; then
      xecho "  ${CYN}Cleaning ${browser} profiles...${DEF}"
      local profile_path
      for profile_path in "${browser_config_dir}/Default" "${browser_config_dir}/Profile"*; do
        if [[ -d "$profile_path" ]]; then
          (cd "$profile_path" && clean_sqlite_dbs)
          rm -rf -- "${profile_path}/"{'Application Cache',Cache,'Code Cache',GPUCache,'Service Worker'} &>/dev/null
        fi
      done
    fi
  done
}

main(){
  print_banner
  [[ ! $EUID == 0 ]] && { sudo -v || sudo true }
  export HOME="${HOME:-/home/${SUDO_USER:-$USER}}"
  local disk_before disk_after space_before space_after
  capture_disk_usage disk_before
  space_before=$(run_priv du -sh / 2>/dev/null | cut -f1)
  xecho "🔄${BLU}Dropping cache...${DEF}"
  sync; echo 3 | run_priv tee /proc/sys/vm/drop_caches &>/dev/null
  if has modprobed-db; then
    modprobed-db store &>/dev/null
    for db in "${HOME}/.config/modprobed.db" "${HOME}/.local/share/modprobed.db"; do
      [[ -f $db ]] && sort -u "$db" -o "$db" &>/dev/null || :
    done
  fi
  xecho "🔄${BLU}Flushing network caches...${DEF}"
  sudo resolvectl flush-caches &>/dev/null; sudo dhclient -r &>/dev/null 
  xecho "🔄${BLU}Removing orphaned packages...${DEF}"
  mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || :)
  [[ ${#orphans[@]} -gt 0 ]] && sudo pacman --noconfirm -Rns "${orphans[@]}" &>/dev/null || :

  find -O2 /etc/pacman.d -maxdepth 1 -type f \( -iname '*.bak' \) -print0 | xargs -0 sudo rm -- &>/dev/null
  find -O2 /etc/pacman.d -maxdepth 1 -type f \( -name '*.pacnew' \) -print0 | xargs -0 sudo rm -- &>/dev/null
  find -O2 /etc/pacman.d -maxdepth 1 -type f \( -name '*-backup' \) -print0 | xargs -0 sudo rm -- &>/dev/null
  xecho "🔄${BLU}Cleaning package cache...${DEF}"
  paru -Sccq --noconfirm &>/dev/null || :
  sudo paccache -rk0 -q || :

  if has cargo-cache; then
    xecho "🔄${BLU}Cleaning Cargo cache...${DEF}"
    cargo cache -efg &>/dev/null; cargo cache -ef trim --limit 1B &>/dev/null
  fi
  
  has uv && uv clean -q
  has bun && bun pm cache rm
  has pnpm && { pnpm prune; pnpm store prune; }
  has sdk && sdk flush tmp &>/dev/null

  xecho "🔄${BLU}Killing CPU-intensive processes...${DEF}"
  while read -r pid; do
    [[ -n $pid ]] && sudo kill -9 "$pid" &>/dev/null || :
  done < <(ps aux --sort=-%cpu 2>/dev/null | awk '{if($3>50.0) print $2}' | tail -n +2)

  xecho "🔄${BLU}Resetting swap space...${DEF}"
  sudo swapoff -a &>/dev/null && sudo swapon -a &>/dev/null

  xecho "🔄${BLU}Cleaning logs and crash dumps...${DEF}"
  sudo find -O2 /var/log/ -iname "*.log" -type f -mtime +7 -delete &>/dev/null || :
  sudo find -O2 /var/crash/ -name "core.*" -type f -mtime +7 -delete &>/dev/null || :
  sudo find -O2 /var/cache/apt/ -name "*.bin" -mtime +7 -delete &>/dev/null || :

  xecho "🔄${BLU}Cleaning user cache...${DEF}"
  find -O2 "${HOME}/.cache" -type f -mtime +1 -delete &>/dev/null || :
  find -O2 "${HOME}/.cache" -type d -empty -delete &>/dev/null || :
  sudo systemd-tmpfiles --clean &>/dev/null || :

  for dir in /var/cache/ /tmp/ /var/tmp/ /var/crash/ /var/lib/systemd/coredump/ "${HOME}/.cache/" /root/.cache/; do
    sudo rm -rf --preserve-root -- "$dir"* &>/dev/null || :
  done

  safe_remove(){ [[ -e $1 ]] && rm -rf --preserve-root -- "$1" &>/dev/null || :; }
  clean_paths(){ for path in "$@"; do [[ -e $path ]] && safe_remove "$path"; done; }

  # Trash
  safe_remove "${HOME}/.local/share/Trash/"*
  sudo rm -rf --preserve-root -- "/root/.local/share/Trash/"* &>/dev/null || :

  local safe_remove_paths=(
    "${HOME}/.local/share/Trash/"*
    "${HOME}/.local/share/flatpak/system-cache/"*
    "/var/tmp/flatpak-cache-"*
    "${HOME}/.thumbnails/"*
    "${HOME}/.var/app/"*/cache/*
    "${HOME}/.var/app/"*/data/Trash/*
    "${HOME}/.config/Trolltech.conf"
    "${HOME}/.local/share/Steam/appcache/"*
    "${HOME}/.nv/ComputeCache/"*
  )
  for path in "${safe_remove_paths[@]}"; do rm -rf --preserve-root -- "$path" &>/dev/null; done

  # Flatpak system caches
  has flatpak && flatpak uninstall --unused --delete-data -y --noninteractive &>/dev/null || :
  has kbuildsycoca6 && kbuildsycoca6 --noincremental &>/dev/null || :
  # System logs
  sudo rm -f --preserve-root -- "/var/log/pacman.log" &>/dev/null || :
  sudo journalctl --flush --sync -q; sudo journalctl --rotate --vacuum-size=1 -q
  sudo rm -rf --preserve-root -- /run/log/journal/* /var/log/journal/* &>/dev/null || :
  sudo rm -rf --preserve-root -- /root/.local/share/zeitgeist/* /home/*/.local/share/zeitgeist/* &>/dev/null || :

  xecho "🔄${BLU}Cleaning shell history files...${DEF}"
  local history_files=(
    .bash_history .zsh_history .history
    .local/share/fish/fish_history .config/fish/fish_history
    .wget-hsts .lesshst
  )
  for file in "${history_files[@]}"; do
    rm -f -- "${HOME}/${file}" &>/dev/null
    run_priv rm -f -- "/root/${file}" &>/dev/null
  done
  touch "${HOME}/.python_history" && run_priv chattr +i "${HOME}/.python_history" &>/dev/null

  clean_browsers "$HOME"
  
  # LibreOffice
  clean_paths "${HOME}/.config/libreoffice/4/user/registrymodifications.xcu" \
    "${HOME}/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu" \
    "${HOME}/snap/libreoffice/"*/.config/libreoffice/4/user/registrymodifications.xcu

  # Steam
  clean_paths "${HOME}/.local/share/Steam/appcache/"* \
    "${HOME}/snap/steam/common/.cache/"* \
    "${HOME}/snap/steam/common/.local/share/Steam/appcache/"* \
    "${HOME}/.var/app/com.valvesoftware.Steam/cache/"* \
    "${HOME}/.var/app/com.valvesoftware.Steam/data/Steam/appcache/"*

  # Python history
  local python_history="${HOME}/.python_history"
  [[ ! -f $python_history ]] && touch "$python_history" || :
  sudo chattr +i "$(realpath "$python_history")" &>/dev/null || :

  clean_firefox(){
    if [[ -d $1 ]]; then
      echo "Cleaning Firefox profile $1"
      cd "$1"
      rm -rf bounce-tracking-protection.sqlite &>/dev/null
      rm -rf blocklist* &>/dev/null
      rm -rf broadcast-listeners.json &>/dev/null
      rm -rf bookmarkbackups &>/dev/null
      rm -rf crashes &>/dev/null
      rm -rf datareporting &>/dev/null
      rm -rf domain_to_categories.* &>/dev/null
      rm -rf minidumps &>/dev/null
      rm -rf saved-telemetry-pings &>/dev/null
      rm -rf addons.* &>/dev/null
      rm -rf AlternateServices.* &>/dev/null
      rm -rf ExperimentStoreData.* &>/dev/null
      rm -rf containers.* &>/dev/null
      rm -rf content-prefs.* &>/dev/null
      rm -rf handlers.* &>/dev/null
      rm -rf kinto.* &>/dev/null
      rm -rf mimeTypes.* &>/dev/null
      rm -rf permissions.* &>/dev/null
      rm -rf pluginreg.* &>/dev/null
      rm -rf secmod.* &>/dev/null
      rm -rf security_state &>/dev/null
      rm -rf serviceworker.* &>/dev/null
      rm -rf sessionstore-logs &>/dev/null
      rm -rf SecurityPreloadState.* &>/dev/null
      rm -rf SiteSecurityServiceState.* &>/dev/null
      rm -rf protections.sqlite &>/dev/null
      rm -rf shield-preference-experiments.* &>/dev/null
      rm -rf storage.* &>/dev/null
      rm -rf Telemetry.ShutdownTime.* &>/dev/null
      rm -rf times.* &>/dev/null
      rm -rf webappsstore.* &>/dev/null
      rm -rf weave &>/dev/null
      cd ..
    fi
  }
  clean_firefox(){
    # 1 argument - path to profile | 2 argument - path to cache directory
    if [[ -d $1 ]]; then
      cd "$1"
      rm -rf "Crash Reports" &>/dev/null
      rm -rf "Pending Pings" &>/dev/null
      # Get a list of profiles directories
      for dir in */; do
        # Remove trailing "/" from the directory name
        dir=${dir%*/}
        clean_firefox_profile "$dir"
      done
    fi
    [[ -d $2/mozilla ]] && rm -rf "$2/mozilla"
    [[ -d $2/fontconfig ]] && rm -rf "$2/fontconfig"
    [[ -d $2/nvidia ]] && rm -rf "$2/nvidia"
  }
  # Mozilla Firefox
  clean_firefox ~/.mozilla/firefox ~/.cache
  clean_firefox ~/snap/firefox/common/.mozilla/firefox ~/snap/firefox/common/.cache

  # Firefox cleanup
  clean_paths "${HOME}/.mozilla/firefox/"*/bookmarkbackups \
    "${HOME}/.mozilla/firefox/"*/saved-telemetry-pings \
    "${HOME}/.mozilla/firefox/"*/sessionstore-logs \
    "${HOME}/.mozilla/firefox/"*/sessionstore-backups \
    "${HOME}/.cache/mozilla/"* \
    "${HOME}/.var/app/org.mozilla.firefox/cache/"* \
    "${HOME}/snap/firefox/common/.cache/"*
  if has python3; then
    python3 <<'EOF'
import glob, os
for pattern in ['~/.mozilla/firefox/*/crashes/*', '~/.mozilla/firefox/*/crashes/events/*']:
  for path in glob.glob(os.path.expanduser(pattern)):
    if os.path.isfile(path):
      try:
        os.remove(path)
      except Exception:
        pass
EOF
  fi
  clean_db(){
    sqlite3 "$1" "VACUUM;" && sqlite3 "$1" "REINDEX;"
    sqlite3 "$1" "PRAGMA optimize"
    find -O2 "$1" -maxdepth 1 -type f -not -name '*.sqlite-wal' -print0 | xargs -0 file -e ascii | sed -n -e "s/:.*SQLite.*//p"
  }

  clean_electron_container(){
    if [[ -d ~/.config/$1 ]]; then
      cd ~/.config
      cd "${1}"
      rm -rf "Application Cache" &>/dev/null
      rm -rf blob_storage &>/dev/null
      rm -rf Cache &>/dev/null
      rm -rf CachedData &>/dev/null
      rm -rf "Code Cache" &>/dev/null
      rm -rf Crashpad &>/dev/null
      rm -rf "Crash Reports" &>/dev/null
      rm -rf "exthost Crash Reports" &>/dev/null
      rm -rf CS_skylib &>/dev/null
      rm -rf databases &>/dev/null
      rm -rf GPUCache &>/dev/null
      rm -rf "Service Worker" &>/dev/null
      rm -rf VideoDecodeStats &>/dev/null
      rm -rf logs &>/dev/null
      rm -rf tmp &>/dev/null
      rm -rf media-stack &>/dev/null
      rm -rf ecscache.json &>/dev/null
      rm -rf skylib &>/dev/null
      rm -rf LOG &>/dev/null
      rm -rf logs.txt &>/dev/null
      rm -rf old_logs_* &>/dev/null
      rm -rf "Network Persistent State" &>/dev/null
      rm -rf QuotaManager &>/dev/null
      rm -rf QuotaManager-journal &>/dev/null
      rm -rf TransportSecurity &>/dev/null
      rm -rf watchdog* &>/dev/null
    fi
  }
  clean_electron_container "Microsoft/Microsoft Teams"
  clean_electron_container "Code - Insiders"
  clean_electron_container "Code - OSS"
  clean_electron_container "Code"
  clean_electron_container "VSCodium"
  clean_electron_container "Void"
  # Handbrake
  clean_directory ~/.config/ghb/EncodeLogs
  # NVIDIA
  rm -rf ~/.config/ghb/Activity.log.* &>/dev/null
  [[ -d ~/.nv ]] && sudo rm -rf ~/.nv
  # GNU parallel
  [[ -d ~/.parallel ]] && rm -rf ~/.parallel
  # WGET hosts file
  [[ -f ~/.wget-hsts ]] && rm -f ~/.wget-hsts
  # Ccache
  command -v ccache &>/dev/null && ccache -C

  # Wine
  clean_paths "${HOME}/.wine/drive_c/windows/temp/"* \
    "${HOME}/.cache/wine/"* \
    "${HOME}/.cache/winetricks/"*

  # GTK
  clean_paths "/.recently-used.xbel" \
    "${HOME}/.local/share/recently-used.xbel" \
    "${HOME}/snap/"*/*/.local/share/recently-used.xbel \
    "${HOME}/.var/app/"*/data/recently-used.xbel

  # KDE
  clean_paths "${HOME}/.local/share/RecentDocuments/"*.desktop \
    "${HOME}/.kde/share/apps/RecentDocuments/"*.desktop \
    "${HOME}/.kde4/share/apps/RecentDocuments/"*.desktop \
    "${HOME}/.var/app/"*/data/*.desktop

  sudo fstrim -a --quiet-unsupported; sudo fstrim -A --quiet-unsupported
  sudo fc-cache -r &>/dev/null || :

  if has bleachbit; then
    xecho "🔄${BLU}Running BleachBit...${DEF}"
    [[ -f ${HOME}/.config/bleachbit/bleachbit.ini ]] && bleachbit -c --preset &>/dev/null || bleachbit -c --all-but-warning &>/dev/null || :
    if has xhost; then
      xhost si:localuser:root &>/dev/null; xhost si:localuser:"$USER" &>/dev/null
      [[ -f ${HOME}/.config/bleachbit/bleachbit.ini ]] && sudo bleachbit -c --preset &>/dev/null || sudo bleachbit -c --all-but-warning &>/dev/null
    elif has pkexec; then
      [[ -f ${HOME}/.config/bleachbit/bleachbit.ini ]] && pkexec bleachbit -c --preset &>/dev/null || pkexec bleachbit -c --all-but-warning &>/dev/null
    else
      xecho "⚠️${YLW}Cannot run BleachBit with elevated privileges${DEF}"
    fi
  fi
  capture_disk_usage disk_after
  space_after=$(run_priv du -sh / | cut -f1)

  xecho
  xecho "${GRN}System cleaned!${DEF}"
  xecho "==> ${BLU}Disk usage before:${DEF} ${disk_before}"
  xecho "==> ${GRN}Disk usage after: ${DEF} ${disk_after}"
  xecho
  xecho "${BLU}Total space before/after:${DEF}"
  xecho "${YLW}Before:${DEF} ${space_before}"
  xecho "${GRN}After: ${DEF} ${space_after}"
}
main "$@"
