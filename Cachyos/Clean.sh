#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar extglob
IFS=$'\n\t'; export LC_ALL=C LANG=C LANGUAGE=C

# Colors
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m' RED=$'\e[31m' GRN=$'\e[32m'
YLW=$'\e[33m' BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m' DEF=$'\e[0m' BLD=$'\e[1m'

# Modes
DEEP=${DEEP:-0}       # aggressive app/browser data purge
NUCLEAR_CLEAN=${NUCLEAR_CLEAN:-0} # allow /var/cache and full ~/.cache nukes (dangerous)

has(){ command -v "$1" &>/dev/null; }

banner(){
  printf '%s\n' "${LBLU} ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ ${DEF}"
  printf '%s\n' "${PNK}██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ ${DEF}"
  printf '%s\n' "${BWHT}██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗${DEF}"
  printf '%s\n' "${PNK}██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║${DEF}"
  printf '%s\n' "${LBLU}╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝${DEF}"
  printf '%s\n' "${LBLU} ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ${DEF}"
}

trap 'cleanup' INT TERM EXIT
cleanup(){ :; }

capture_disk_usage(){ local -n ref=$1; ref=$(df -h --output=used,pcent / | awk 'NR==2{print $1, $2}'); }

# NUL-safe finder using fdf/fd/find
find0(){ # usage: find0 <path> <find-args...> (prints NUL-delimited)
  local root=$1; shift
  if has fdf; then fdf -H -0 --color=never "$@" . "$root"
  elif has fd; then fd -H -0 --color=never "$@" . "$root"
  else find "$root" "$@" -print0
  fi
}

ensure_not_running_any(){ local timeout=6 p
  for p in "$@"; do
    if pgrep -x -u "$USER" "$p" &>/dev/null; then
      printf '  %s\n' "${YLW}Waiting for ${p} to exit...${DEF}"
      while ((timeout-->0)) && pgrep -x -u "$USER" "$p" &>/dev/null; do read -rt 1 -- <> <(:) &>/dev/null || :; done
      pgrep -x -u "$USER" "$p" &>/dev/null && { printf '  %s\n' "${RED}Killing ${p}...${DEF}"; pkill -KILL -x -u "$USER" "$p" &>/dev/null || :; read -rt 1 -- <> <(:) &>/dev/null || :; }
    fi
  done
}

# SQLite maintenance
vacuum_sqlite(){ # echo bytes_saved
  local db=$1 s_old s_new
  [[ -f $db ]] || { printf '0\n'; return; }
  # skip if probably open
  [[ -f ${db}-wal || -f ${db}-journal ]] && { printf '0\n'; return; }
  s_old=$(stat -c%s "$db" 2>/dev/null) || { printf '0\n'; return; }
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; REINDEX; PRAGMA optimize;' &>/dev/null || { printf '0\n'; return; }
  s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
  printf '%d\n' "$((s_old - s_new))"
}

clean_sqlite_dbs(){ # in CWD
  local total=0 db saved
  while IFS= read -r -d '' db; do
    if file -e ascii -b "$db" | grep -q 'SQLite'; then
      saved=$(vacuum_sqlite "$db" || printf '0')
      ((saved>0)) && total=$((total+saved))
    fi
  done < <(find0 . -maxdepth 1 -type f)
  ((total>0)) && printf '  %s\n' "${GRN}Vacuumed SQLite DBs, saved $((total/1024)) KB${DEF}"
}

# Firefox-family profile discovery
foxdir(){ # echo ACTIVE profile dir for a base like ~/.mozilla/firefox or ~/.librewolf
  local base=$1 p
  [[ -d $base ]] || return 1
  if [[ -f $base/installs.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini")
    [[ -n $p && -d $base/$p ]] && { printf '%s\n' "$base/$p"; return 0; }
  fi
  if [[ -f $base/profiles.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{s=0} /^\[Profile[0-9]+\]/{s=1} s&&/^Default=1/{d=1} s&&/^Path=/{if(d){print $2;exit}}' "$base/profiles.ini")
    [[ -n $p && -d $base/$p ]] && { printf '%s\n' "$base/$p"; return 0; }
  fi
  return 1
}

mozilla_profiles(){ # print all profile dirs for a base containing installs.ini/profiles.ini
  local base=$1 line p; declare -A seen
  [[ -d $base ]] || return 0
  if [[ -f $base/installs.ini ]]; then
    while IFS= read -r line; do
      [[ $line == Default=* ]] || continue
      p=${line#Default=}; [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s\n' "$base/$p"; seen[$p]=1; }
    done < "$base/installs.ini"
  fi
  if [[ -f $base/profiles.ini ]]; then
    while IFS= read -r line; do
      [[ $line == Path=* ]] || continue
      p=${line#Path=}; [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s\n' "$base/$p"; seen[$p]=1; }
    done < "$base/profiles.ini"
  fi
}

# Chromium roots (native/flatpak/snap)
chrome_roots_for(){ # $1 product key
  case "$1" in
    chrome) printf '%s\n' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;;
    chromium) printf '%s\n' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;;
    brave) printf '%s\n' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;;
    opera) printf '%s\n' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;;
    *) : ;;
  esac
}

chrome_profiles(){ # list Default + Profile * dirs under a root
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s\n' "$d"; done
}

# Borrow Seryoga's lists (gated by DEEP to avoid UX breakage by default)
chrome_root_prune(){ # $1=root dir
  local r=$1
  # Safe root-level junk
  rm -rf "$r"/{BrowserMetrics*,GraphiteDawnCache,OptimizationHints,ShaderCache,Variations,"Webstore Downloads",*_crx_cache,hyphen-data,screen_ai,segmentation_platform,MEIPreload,PKIMetadata,Policy,OriginTrials,UrlParamClassifications,ClientSidePhishing,"Certificate Revocation Lists",ZxcvbnData,"Crowd Deny","Consent To Send Stats"} &>/dev/null || :
  ((DEEP>0)) && rm -rf "$r"/{NativeMessagingHosts,FirstPartySetsPreloaded,OnDeviceHeadSuggestModel,TrustTokenKeyCommitments,SSLErrorAssistant,PrivacySandboxAttestationsPreloaded,OptimizationHints,EVWhitelist,Floc,DesktopSharingHub,TLSDeprecationConfig,WidevineCdm,FirstPartySetsPreloaded,TpcdMetadata} &>/dev/null || :
}

chrome_profile_prune(){ # $1=profile dir
  local p=$1
  # Safe caches/logs
  rm -rf "$p"/{'Application Cache','Code Cache',GPUCache,blob_storage,Logs,LOG,LOG.old,MANIFEST-*,Thumbnails,"Download Service",'Service Worker',"GCM Store","Feature Engagement Tracker",Dawn*Cache} &>/dev/null || :
  rm -rf "$p"/{Network*,"Reporting and NEL","Reporting and NEL-journal","Search Logos","VideoDecodeStats","WebRTC Logs","WebrtcVideoStats","webrtc_event_logs"} &>/dev/null || :
  rm -rf "$p"/{QuotaManager*,'Extension State',"Managed Extension Settings"} &>/dev/null || :
  # Aggressive (may reset site data/sign-ins)
  if ((DEEP>0)); then
    rm -rf "$p"/{IndexedDB,"Local Storage","Session Storage",Storage,shared_proto_db,"Top Sites","Top Sites-journal","Site Characteristics Database","Platform Notifications","Pepper Data","Affiliation Database","Affiliation Database-journal","Translate Ranker Model","Secure Preferences","Extension Cookies","Extension Cookies-journal","Trust Tokens","Trust Tokens-journal",SharedStorage*,PrivateAggregation*,"Safe Browsing Cookies","Safe Browsing Cookies-journal",Shortcuts*,DownloadMetadata,LOCK,*.log,*.ldb,in_progress_download_metadata_store,"Sync Data","Segmentation Platform",chrome_cart_db,discounts_db,feedv2,parcel_tracking_db,PersistentOriginTrials,heavy_ad_intervention_opt_out.*,previews_opt_out.*,page_load_capping_opt_out.*,ads_service,Accounts,"File System"} &>/dev/null || :
  fi
}

clean_browsers(){
  printf '%s\n' "🔄${BLU}Cleaning browsers...${DEF}"

  # Firefox family (native, flatpak, snap)
  local moz_bases=(
    "$HOME/.mozilla/firefox"
    "$HOME/.librewolf"
    "$HOME/.floorp"
    "$HOME/.waterfox"
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
    "$HOME/.var/app/io.gitlab.librewolf-community/.mozilla/firefox"
    "$HOME/snap/firefox/common/.mozilla/firefox"
  )
  ensure_not_running_any firefox librewolf floorp waterfox
  local b base prof
  for base in "${moz_bases[@]}"; do
    [[ -d $base ]] || continue
    # Waterfox channels
    if [[ $base == "$HOME/.waterfox" ]]; then
      while IFS= read -r -d '' b; do
        while IFS= read -r prof; do
          [[ -d $prof ]] || continue
          (cd "$prof" && clean_sqlite_dbs)
          ((DEEP>0)) && rm -rf "$prof"/{bookmarkbackups,crashes,datareporting,minidumps,saved-telemetry-pings,sessionstore-logs,storage.*,"Crash Reports","Pending Pings"} &>/dev/null || :
        done < <(mozilla_profiles "$b")
      done < <(find0 "$base" -maxdepth 1 -type d)
      continue
    fi
    # Normal bases
    while IFS= read -r prof; do
      [[ -d $prof ]] || continue
      (cd "$prof" && clean_sqlite_dbs)
      ((DEEP>0)) && rm -rf "$prof"/{bookmarkbackups,crashes,datareporting,minidumps,saved-telemetry-pings,sessionstore-logs,storage.*,"Crash Reports","Pending Pings"} &>/dev/null || :
    done < <(mozilla_profiles "$base")
  done
  rm -rf "$HOME/.cache/mozilla"/* "$HOME/.var/app/org.mozilla.firefox/cache"/* "$HOME/snap/firefox/common/.cache"/* &>/dev/null || :

  # Chromium family
  ensure_not_running_any google-chrome chromium brave-browser brave opera opera-beta opera-developer
  local chrome_products=(chrome chromium brave opera)
  local root profdir
  for b in "${chrome_products[@]}"; do
    while IFS= read -r root; do
      [[ -d $root ]] || continue
      chrome_root_prune "$root"
      while IFS= read -r profdir; do
        [[ -d $profdir ]] || continue
        (cd "$profdir" && clean_sqlite_dbs)
        chrome_profile_prune "$profdir"
      done < <(chrome_profiles "$root")
    done < <(chrome_roots_for "$b")
  done
}

# Electron containers (subset + safe caches)
clean_electron_container(){ # arg is config folder under ~/.config
  local d="$HOME/.config/$1"
  [[ -d $d ]] || return
  rm -rf "$d"/{"Application Cache",blob_storage,Cache,CachedData,"Code Cache",Crashpad,"Crash Reports","exthost Crash Reports",GPUCache,"Service Worker",VideoDecodeStats,logs,tmp,LOG,logs.txt,old_logs_*,"Network Persistent State",QuotaManager,QuotaManager-journal,TransportSecurity,watchdog*} &>/dev/null || :
}
clean_electron(){
  local apps=("Microsoft/Microsoft Teams" "Code - Insiders" "Code - OSS" "Code" "VSCodium")
  local a; for a in "${apps[@]}"; do clean_electron_container "$a"; done
}

# Privacy and misc app junk
privacy_clean(){
  printf '%s\n' "🔒${MGN}Privacy cleanup...${DEF}"
  rm -f "$HOME"/.{bash,zsh}_history "$HOME"/.history "$HOME"/.local/share/fish/fish_history "$HOME"/.config/fish/fish_history "$HOME"/.{wget,less,python}_history &>/dev/null || :
  sudo rm -f /root/.{bash,zsh,python}_history /root/.history /root/.local/share/fish/fish_history /root/.config/fish/fish_history &>/dev/null || :
  touch "$HOME/.python_history" && sudo chattr +i "$HOME/.python_history" &>/dev/null || :
  # Steam, Wine, thumbnails, GTK/KDE recents
  rm -rf "$HOME/.local/share/Steam/appcache"/* "$HOME/.cache/wine"/* "$HOME/.cache/winetricks"/* &>/dev/null || :
  rm -rf "$HOME"/.thumbnails/* "$HOME"/.cache/thumbnails/* &>/dev/null || :
  rm -f "$HOME"/.recently-used.xbel "$HOME"/.local/share/recently-used.xbel* &>/dev/null || :
  rm -rf "$HOME"/.local/share/RecentDocuments/*.desktop "$HOME"/.kde/share/apps/RecentDocuments/*.desktop "$HOME"/.kde4/share/apps/RecentDocuments/*.desktop &>/dev/null || :
  # VS Code user caches
  rm -rf "$HOME/.config/Code"/{"Crash Reports","exthost Crash Reports",Cache,CachedData,"Code Cache",GPUCache,CachedExtensions,CachedExtensionVSIXs,logs}/* &>/dev/null || :
  rm -rf "$HOME/.var/app/com.visualstudio.code/config/Code"/{"Crash Reports","exthost Crash Reports",Cache,CachedData,"Code Cache",GPUCache,CachedExtensions,CachedExtensionVSIXs,logs}/* &>/dev/null || :
  # HandBrake logs
  rm -rf "$HOME/.config/ghb/EncodeLogs"/* "$HOME/.config/ghb/Activity.log."* &>/dev/null || :
  # NVIDIA user cache
  [[ -d "$HOME/.nv" ]] && sudo rm -rf "$HOME/.nv" &>/dev/null || :
}

pkg_cache_clean(){
  if has pacman; then
    sudo paccache -rk0 -q &>/dev/null || :
    if has paru; then paru -Scc --noconfirm &>/dev/null || :; else sudo pacman -Scc --noconfirm &>/dev/null || :; fi
  fi
  if has apt-get; then sudo apt-get clean &>/dev/null || :; sudo apt-get autoclean &>/dev/null || :; fi
}

snap_flatpak_trim(){
  has flatpak && flatpak uninstall --unused --delete-data -y &>/dev/null || :
  if has snap; then
    printf '%s\n' "🔄${BLU}Removing old Snap revisions...${DEF}"
    snap list --all | while read -r name version rev tracking publisher notes; do
      [[ ${notes:-} == *disabled* ]] && sudo snap remove "$name" --revision="$rev" &>/dev/null || :
    done
    rm -rf "$HOME"/snap/*/*/.cache/* &>/dev/null || :
  fi
  sudo rm -rf /var/lib/snapd/cache/* /var/tmp/flatpak-cache-* &>/dev/null || :
}

system_clean(){
  printf '%s\n' "🔄${BLU}System cleanup...${DEF}"
  sudo resolvectl flush-caches &>/dev/null || :
  sudo systemd-resolve --flush-caches &>/dev/null || :
  sudo systemd-resolve --reset-statistics &>/dev/null || :
  pkg_cache_clean
  sudo journalctl --rotate -q &>/dev/null || :
  sudo journalctl --vacuum-size=10M -q &>/dev/null || :
  sudo find /var/log -type f -name '*.old' -delete &>/dev/null || :
  sudo swapoff -a &>/dev/null || :; sudo swapon -a &>/dev/null || :
  sudo systemd-tmpfiles --clean &>/dev/null || :
  # Caches (safe)
  rm -rf "$HOME/.local/share/Trash"/* "$HOME/.nv/ComputeCache"/* &>/dev/null || :
  rm -rf "$HOME/.var/app"/*/cache/* &>/dev/null || :
  ((NUCLEAR_CLEAN>0)) && { rm -rf "$HOME/.cache"/* &>/dev/null || :; sudo rm -rf /var/cache/* &>/dev/null || :; }
  sudo rm -rf /tmp/* /var/tmp/* &>/dev/null || :
  has bleachbit && { bleachbit -c --preset &>/dev/null || :; sudo bleachbit -c --preset &>/dev/null || :; }
  sudo fstrim -a --quiet-unsupported &>/dev/null || :
  has fc-cache && sudo fc-cache -r &>/dev/null || :
}

main(){
  banner
  [[ $EUID -ne 0 ]] && sudo -v || :
  local disk_before disk_after space_before space_after
  capture_disk_usage disk_before
  space_before=$(sudo du -sh / 2>/dev/null | cut -f1)
  sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null || :
  # Dev caches
  if has cargo-cache; then cargo cache -efg &>/dev/null || :; cargo cache -ef trim --limit 1B &>/dev/null || :; fi
  has uv && uv clean -q || :
  has bun && bun pm cache rm &>/dev/null || :
  has pnpm && { pnpm prune &>/dev/null || :; pnpm store prune &>/dev/null || :; }
  has sdk && sdk flush tmp &>/dev/null || :

  clean_browsers
  clean_electron
  privacy_clean
  snap_flatpak_trim
  system_clean

  capture_disk_usage disk_after
  space_after=$(sudo du -sh / 2>/dev/null | cut -f1)
  printf '\n%s\n' "${GRN}System cleaned${DEF}"
  printf '==> %s %s\n' "${BLU}Disk usage before:${DEF}" "$disk_before"
  printf '==> %s %s\n' "${GRN}Disk usage after:${DEF}" "$disk_after"
  printf '%s %s\n' "${YLW}Before:${DEF}" "$space_before"
  printf '%s %s\n' "${GRN}After:${DEF}" "$space_after"
}

main "$@"
