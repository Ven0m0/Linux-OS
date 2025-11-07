#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh" || exit 1

# Modes
DEEP=${DEEP:-0}       # aggressive app/browser data purge
NUCLEAR_CLEAN=${NUCLEAR_CLEAN:-0} # allow /var/cache and full ~/.cache nukes (dangerous)

# Initialize privilege tool
PRIV_CMD=$(init_priv)
export PRIV_CMD

trap 'cleanup' INT TERM EXIT
cleanup(){ :; }

banner(){
  printf '%s\n' "${LBLU} ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ ${DEF}"
  printf '%s\n' "${PNK}██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ ${DEF}"
  printf '%s\n' "${BWHT}██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗${DEF}"
  printf '%s\n' "${PNK}██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║${DEF}"
  printf '%s\n' "${LBLU}╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝${DEF}"
  printf '%s\n' "${LBLU} ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ${DEF}"
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
  run_priv rm -f /root/.{bash,zsh,python}_history /root/.history /root/.local/share/fish/fish_history /root/.config/fish/fish_history &>/dev/null || :
  touch "$HOME/.python_history" && run_priv chattr +i "$HOME/.python_history" &>/dev/null || :
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
  [[ -d "$HOME/.nv" ]] && run_priv rm -rf "$HOME/.nv" &>/dev/null || :
}

pkg_cache_clean(){
  if has pacman; then
    run_priv paccache -rk0 -q &>/dev/null || :
    if has paru; then paru -Scc --noconfirm &>/dev/null || :; else run_priv pacman -Scc --noconfirm &>/dev/null || :; fi
  fi
  if has apt-get; then run_priv apt-get clean &>/dev/null || :; run_priv apt-get autoclean &>/dev/null || :; fi
}

snap_flatpak_trim(){
  has flatpak && flatpak uninstall --unused --delete-data -y &>/dev/null || :
  if has snap; then
    printf '%s\n' "🔄${BLU}Removing old Snap revisions...${DEF}"
    snap list --all | while read -r name version rev tracking publisher notes; do
      [[ ${notes:-} == *disabled* ]] && run_priv snap remove "$name" --revision="$rev" &>/dev/null || :
    done
    rm -rf "$HOME"/snap/*/*/.cache/* &>/dev/null || :
  fi
  run_priv rm -rf /var/lib/snapd/cache/* /var/tmp/flatpak-cache-* &>/dev/null || :
}

system_clean(){
  printf '%s\n' "🔄${BLU}System cleanup...${DEF}"
  run_priv resolvectl flush-caches &>/dev/null || :
  run_priv systemd-resolve --flush-caches &>/dev/null || :
  run_priv systemd-resolve --reset-statistics &>/dev/null || :
  pkg_cache_clean
  run_priv journalctl --rotate -q &>/dev/null || :
  run_priv journalctl --vacuum-size=10M -q &>/dev/null || :
  run_priv find /var/log -type f -name '*.old' -delete &>/dev/null || :
  run_priv swapoff -a &>/dev/null || :; run_priv swapon -a &>/dev/null || :
  run_priv systemd-tmpfiles --clean &>/dev/null || :
  # Caches (safe)
  rm -rf "$HOME/.local/share/Trash"/* "$HOME/.nv/ComputeCache"/* &>/dev/null || :
  rm -rf "$HOME/.var/app"/*/cache/* &>/dev/null || :
  ((NUCLEAR_CLEAN>0)) && { rm -rf "$HOME/.cache"/* &>/dev/null || :; run_priv rm -rf /var/cache/* &>/dev/null || :; }
  run_priv rm -rf /tmp/* /var/tmp/* &>/dev/null || :
  has bleachbit && { bleachbit -c --preset &>/dev/null || :; run_priv bleachbit -c --preset &>/dev/null || :; }
  run_priv fstrim -a --quiet-unsupported &>/dev/null || :
  has fc-cache && run_priv fc-cache -r &>/dev/null || :
}

main(){
  banner
  [[ $EUID -ne 0 ]] && "$PRIV_CMD" -v || :
  local disk_before disk_after space_before space_after
  capture_disk_usage disk_before
  space_before=$(run_priv du -sh / 2>/dev/null | cut -f1)
  sync; echo 3 | run_priv tee /proc/sys/vm/drop_caches &>/dev/null || :
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
  space_after=$(run_priv du -sh / 2>/dev/null | cut -f1)
  printf '\n%s\n' "${GRN}System cleaned${DEF}"
  printf '==> %s %s\n' "${BLU}Disk usage before:${DEF}" "$disk_before"
  printf '==> %s %s\n' "${GRN}Disk usage after:${DEF}" "$disk_after"
  printf '%s %s\n' "${YLW}Before:${DEF}" "$space_before"
  printf '%s %s\n' "${GRN}After:${DEF}" "$space_after"
}

main "$@"
