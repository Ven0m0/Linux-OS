#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar extglob
set -CE
IFS=$'\n\t' LC_ALL=C LANG=C LANGUAGE=C SHELL=bash
#============ Color & Effects ============
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
has(){ command -v "$1" &>/dev/null; }
xecho(){ printf '%b\n' "$*"; }

#============ Privilege Helper ==========
get_priv_cmd(){
  local cmd
  for cmd in sudo-rs sudo doas; do
    if has "$cmd"; then
      printf '%s' "$cmd"; return 0
    fi
  done
  [[ $EUID -eq 0 ]] && printf '' || { xecho "${RED}No privilege tool found${DEF}" >&2; exit 1; }
}
PRIV_CMD=$(get_priv_cmd)
[[ -n $PRIV_CMD && $EUID -ne 0 ]] && "$PRIV_CMD" -v
run_priv(){ [[ $EUID -eq 0 || -z $PRIV_CMD ]] && "$@" || "$PRIV_CMD" -- "$@"; }

print_banner(){
  local banner flag_colors
  banner=$(cat <<'EOF'
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
    for line in "${lines[@]}"; do
      printf '%s%s%s\n' "${flag_colors[0]}" "$line" "$DEF"
    done
  else
    for i in "${!lines[@]}"; do
      local segment_index=$(( i * (segments - 1) / (line_count - 1) ))
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
  local var_name=$1
  local -n ref=$var_name
  ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}

main(){
  print_banner
  [[ $EUID -ne 0 ]] && run_priv true
  export HOME="${HOME:-/home/${SUDO_USER:-$USER}}"
  local disk_before disk_after space_before space_after
  capture_disk_usage disk_before
  space_before=$(run_priv du -sh / 2>/dev/null | cut -f1)
  
  sync
  xecho "🔄${BLU}Dropping cache...${DEF}"
  echo 3 | run_priv tee /proc/sys/vm/drop_caches &>/dev/null
  if has modprobed-db; then
    xecho "🔄${BLU}Storing kernel modules...${DEF}"
    run_priv modprobed-db store
    for db in "${HOME}/.config/modprobed.db" "${HOME}/.local/share/modprobed.db"; do
      [[ -f $db ]] && sort -u "$db" -o "$db" &>/dev/null || :
    done
  fi
  xecho "🔄${BLU}Flushing network caches...${DEF}"
  has dhclient && dhclient -r &>/dev/null || :
  run_priv resolvectl flush-caches &>/dev/null || :
  xecho "🔄${BLU}Removing orphaned packages...${DEF}"
  mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || :)
  if [[ ${#orphans[@]} -gt 0 ]]; then
    run_priv pacman -Rns "${orphans[@]}" --noconfirm &>/dev/null || :
  fi
  find /etc/pacman.d -maxdepth 1 -type f \( -name '*.bak' \) -print0 | xargs -0 sudo rm -- &>/dev/null
  xecho "🔄${BLU}Cleaning package cache...${DEF}"
  run_priv pacman -Scc --noconfirm &>/dev/null || :
  run_priv paccache -rk0 -q &>/dev/null || :

  if has uv; then
    xecho "🔄${BLU}Cleaning UV cache...${DEF}"
    uv cache prune -q &>/dev/null || :
    uv cache clean -q &>/dev/null || :
  fi
  if has cargo-cache; then
    xecho "🔄${BLU}Cleaning Cargo cache...${DEF}"
    cargo cache -efg &>/dev/null || :
    cargo cache -efg trim --limit 1B &>/dev/null || :
    cargo cache -efg clean-unref &>/dev/null || :
  fi

  xecho "🔄${BLU}Killing CPU-intensive processes...${DEF}"
  while read -r pid; do
    [[ -n $pid ]] && run_priv kill -9 "$pid" &>/dev/null || :
  done < <(ps aux --sort=-%cpu 2>/dev/null | awk '{if($3>50.0) print $2}' | tail -n +2)

  xecho "🔄${BLU}Resetting swap space...${DEF}"
  run_priv swapoff -a &>/dev/null && run_priv swapon -a &>/dev/null
  
  xecho "🔄${BLU}Cleaning logs and crash dumps...${DEF}"
  run_priv find /var/log/ -name "*.log" -type f -mtime +7 -delete &>/dev/null || :
  run_priv find /var/crash/ -name "core.*" -type f -mtime +7 -delete &>/dev/null || :
  run_priv find /var/cache/apt/ -name "*.bin" -mtime +7 -delete &>/dev/null || :

  xecho "🔄${BLU}Cleaning user cache...${DEF}"
  find "${HOME}/.cache" -type f -mtime +1 -delete &>/dev/null || :
  find "${HOME}/.cache" -type d -empty -delete &>/dev/null || :
  run_priv systemd-tmpfiles --clean &>/dev/null || :

  for dir in /var/cache/ /tmp/ /var/tmp/ /var/crash/ /var/lib/systemd/coredump/ "${HOME}/.cache/" /root/.cache/; do
    run_priv rm -rf --preserve-root -- "${dir}"* &>/dev/null || :
  done

  safe_remove(){ [[ -e $1 ]] && rm -rf --preserve-root -- "$1" &>/dev/null || :; }
  clean_paths(){ for path in "$@"; do [[ -e $path ]] && safe_remove "$path"; done; }

  # Flatpak cache
  safe_remove "${HOME}/.var/app/"*/cache/*
  safe_remove "${HOME}/.config/Trolltech.conf"
  has kbuildsycoca6 && kbuildsycoca6 --noincremental &>/dev/null || :

  # Trash
  safe_remove "${HOME}/.local/share/Trash/"*
  run_priv rm -rf --preserve-root -- "/root/.local/share/Trash/"* &>/dev/null || :

  # Flatpak system caches
  if has flatpak; then
    flatpak uninstall --unused --delete-data -y --noninteractive &>/dev/null || :
    run_priv rm -rf --preserve-root -- /var/tmp/flatpak-cache-* &>/dev/null || :
    safe_remove "${HOME}/.cache/flatpak/system-cache/"*
    safe_remove "${HOME}/.local/share/flatpak/system-cache/"*
    safe_remove "${HOME}/.var/app/"*/data/Trash/*
  fi
  safe_remove "${HOME}/.thumbnails/"*

  # System logs
  run_priv rm -f --preserve-root -- "/var/log/pacman.log" &>/dev/null || :
  run_priv journalctl --rotate --vacuum-size=1 --flush --sync -q &>/dev/null || :
  run_priv rm -rf --preserve-root -- /run/log/journal/* /var/log/journal/* &>/dev/null || :
  run_priv rm -rf --preserve-root -- /root/.local/share/zeitgeist/* /home/*/.local/share/zeitgeist/* &>/dev/null || :

  # History
  for file in \
    "${HOME}/.wget-hsts" "${HOME}/.curl-hsts" "${HOME}/.lesshst" "${HOME}/nohup.out" "${HOME}/token" \
    "${HOME}/.local/share/fish/fish_history" "${HOME}/.config/fish/fish_history" \
    "${HOME}/.zsh_history" "${HOME}/.bash_history" "${HOME}/.history"; do
    safe_remove "$file"
  done
  for file in \
    "/root/.local/share/fish/fish_history" "/root/.config/fish/fish_history" \
    "/root/.zsh_history" "/root/.bash_history" "/root/.history"; do
    run_priv rm -f --preserve-root -- "$file" &>/dev/null || :
  done

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

  # NVIDIA
  run_priv rm -rf --preserve-root -- "${HOME}/.nv/ComputeCache/"* &>/dev/null || :

  # Python history
  local python_history="${HOME}/.python_history"
  [[ ! -f $python_history ]] && touch "$python_history" || :
  run_priv chattr +i "$(realpath "$python_history")" &>/dev/null || :

  clean_firefox(){
    if [[ -d $1 ]]; then
      echo "Cleaning Firefox profile $1"
      cd "$1"
      rm -rf &>/dev/null bounce-tracking-protection.sqlite
      rm -rf &>/dev/null blocklist*
      rm -rf &>/dev/null broadcast-listeners.json
      rm -rf &>/dev/null bookmarkbackups
      rm -rf &>/dev/null crashes
      rm -rf &>/dev/null datareporting
      rm -rf &>/dev/null domain_to_categories.*
      rm -rf &>/dev/null minidumps
      rm -rf &>/dev/null saved-telemetry-pings
      rm -rf &>/dev/null addons.*
      rm -rf &>/dev/null AlternateServices.*
      rm -rf &>/dev/null ExperimentStoreData.*
      rm -rf &>/dev/null containers.*
      rm -rf &>/dev/null content-prefs.*
      rm -rf &>/dev/null handlers.*
      rm -rf &>/dev/null kinto.*
      rm -rf &>/dev/null mimeTypes.*
      rm -rf &>/dev/null permissions.*
      rm -rf &>/dev/null pluginreg.*
      rm -rf &>/dev/null secmod.*
      rm -rf &>/dev/null security_state
      rm -rf &>/dev/null serviceworker.*
      rm -rf &>/dev/null sessionstore-logs
      rm -rf &>/dev/null SecurityPreloadState.*
      rm -rf &>/dev/null SiteSecurityServiceState.*
      rm -rf &>/dev/null protections.sqlite
      rm -rf &>/dev/null shield-preference-experiments.*
      rm -rf &>/dev/null storage.*
      rm -rf &>/dev/null Telemetry.ShutdownTime.*
      rm -rf &>/dev/null times.*
      rm -rf &>/dev/null webappsstore.*
      rm -rf &>/dev/null weave
      cd ..
    fi
  }
  clean_firefox(){
    # 1 argument - path to profile | 2 argument - path to cache directory
    if [[ -d $1 ]]; then
      cd "$1"
      rm -rf &>/dev/null "Crash Reports"
      rm -rf &>/dev/null "Pending Pings"
      # Get a list of profiles directories
      for dir in */; do
      # Remove trailing "/" from the directory name
      dir=${dir%*/}
        clean_firefox_profile $dir
      done
    fi
    [[ -d $2/mozilla ]] && rm -rf "$2/mozilla";
    [[ -d $2/fontconfig ]] && rm -rf "$2/fontconfig";
    [[ -d $2/nvidia ]] && rm -rf "$2/nvidia";
  }
  # Mozilla Firefox
  clean_firefox ~/.mozilla/firefox ~/.cache
  clean_firefox ~/snap/firefox/common/.mozilla/firefox ~/snap/firefox/common/.cache

  clean_electron_container (){
    if [[ -d ~/.config/$1 ]]; then
      cd ~/.config
      cd "${1}"
      rm -rf &>/dev/null "Application Cache"
      rm -rf &>/dev/null blob_storage
      rm -rf &>/dev/null Cache
      rm -rf &>/dev/null CachedData
      rm -rf &>/dev/null "Code Cache"
      rm -rf &>/dev/null Crashpad
      rm -rf &>/dev/null "Crash Reports"
      rm -rf &>/dev/null "exthost Crash Reports"
      rm -rf &>/dev/null CS_skylib
      rm -rf &>/dev/null databases
      rm -rf &>/dev/null GPUCache
      rm -rf &>/dev/null "Service Worker"
      rm -rf &>/dev/null VideoDecodeStats
      rm -rf &>/dev/null logs
      rm -rf &>/dev/null tmp
      rm -rf &>/dev/null media-stack
      rm -rf &>/dev/null ecscache.json
      rm -rf &>/dev/null skylib
      rm -rf &>/dev/null LOG
      rm -rf &>/dev/null logs.txt
      rm -rf &>/dev/null old_logs_*
      rm -rf &>/dev/null "Network Persistent State"
      rm -rf &>/dev/null QuotaManager
      rm -rf &>/dev/null QuotaManager-journal
      rm -rf &>/dev/null TransportSecurity
      rm -rf &>/dev/null watchdog*
    fi
  }
  clean_electron_container "Microsoft/Microsoft Teams"
  clean_electron_container "Code - Insiders"
  clean_electron_container "Code - OSS"
  clean_electron_container "Code"

  # Handbrake
  clean_directory ~/.config/ghb/EncodeLogs
  # NVIDIA
  rm -rf &>/dev/null ~/.config/ghb/Activity.log.*
  [[ -d ~/.nv ]] && sudo rm -rf ~/.nv;

  # GNU parallel
  [[ -d ~/.parallel ]] && rm -rf ~/.parallel;

  # WGET hosts file
  [[ -f ~/.wget-hsts ]] && rm -f ~/.wget-hsts;

  command -v ccache &>/dev/null && ccache -C
  
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
    sqlite3 "$1" vacuum
    sqlite3 "$1" reindex
    sqlite3 "$1" "PRAGMA optimize"
  }
  find -L "$@" -maxdepth 2 -type f -not -name '*.sqlite-wal' -print0 2>/dev/null | xargs -0 file -e ascii | sed -n -e "s/:.*SQLite.*//p"
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

  run_priv fstrim -a --quiet-unsupported &>/dev/null || :
  run_priv fc-cache -f &>/dev/null || :

  has sdk && sdk flush tmp &>/dev/null || :

  if has bleachbit; then
    xecho "🔄${BLU}Running BleachBit...${DEF}"
    bleachbit -c --preset &>/dev/null || :
    if has xhost; then
      xhost si:localuser:root &>/dev/null || :
      xhost si:localuser:"$USER" &>/dev/null || :
      run_priv bleachbit -c --preset &>/dev/null || :
    elif has pkexec; then
      pkexec bleachbit -c --preset &>/dev/null || :
    else
      xecho "⚠️${YLW}Cannot run BleachBit with elevated privileges${DEF}"
    fi
  fi

  capture_disk_usage disk_after
  space_after=$(run_priv du -sh / 2>/dev/null | cut -f1)

  xecho "${GRN}System cleaned!${DEF}"
  xecho "==> ${BLU}Disk usage before cleanup:${DEF} ${disk_before}"
  xecho "==> ${GRN}Disk usage after cleanup: ${DEF} ${disk_after}"
  xecho
  xecho "${BLU}Space before/after:${DEF}"
  xecho "${YLW}Before:${DEF} ${space_before}"
  xecho "${GRN}After: ${DEF} ${space_after}"
}

main "$@"
