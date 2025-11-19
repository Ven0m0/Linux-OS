#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============ Inlined from lib/common.sh ============
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# Export common locale settings
export LC_ALL=C LANG=C LANGUAGE=C

#============ Color & Effects ============
# Trans flag color palette (LBLU → PNK → BWHT → PNK → LBLU)
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Export color variables so they're available to sourcing scripts
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD

#============ Core Helper Functions ============
# Check if command exists
has(){ command -v "$1" &>/dev/null; }

# Echo with formatting support
xecho(){ printf '%b\n' "$*"; }
# Logging functions
log(){ xecho "$*"; }
die(){ xecho "${RED}Error:${DEF} $*" >&2; exit 1; }

# Confirmation prompt
confirm(){
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

#============ Privilege Escalation ============
# Detect available privilege escalation tool
get_priv_cmd(){
  local cmd
  for cmd in sudo-rs sudo doas; do
    if has "$cmd"; then
      printf '%s' "$cmd"
      return 0
    fi
  done
  [[ $EUID -eq 0 ]] || die "No privilege tool found and not running as root"
  printf ''
}

# Initialize privilege tool
init_priv(){
  local priv_cmd; priv_cmd=$(get_priv_cmd)
  [[ -n $priv_cmd && $EUID -ne 0 ]] && "$priv_cmd" -v
  printf '%s' "$priv_cmd"
}
# Run command with privilege escalation
run_priv(){
  local priv_cmd="${PRIV_CMD:-}"
  [[ -z $priv_cmd ]] && priv_cmd=$(get_priv_cmd)
  if [[ $EUID -eq 0 || -z $priv_cmd ]]; then
    "$@"
  else
    "$priv_cmd" -- "$@"
  fi
}

#============ Banner Printing Functions ============
# Print banner with trans flag gradient
# Usage: print_banner "banner_text" [title]
print_banner(){
  local banner="$1" title="${2:-}"
  local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")

  # Optimized: Use read loop instead of mapfile to avoid subprocess
  local -a lines=()
  while IFS= read -r line || [[ -n $line ]]; do
    lines+=("$line")
  done <<<"$banner"

  local line_count=${#lines[@]} segments=${#flag_colors[@]}
  if ((line_count <= 1)); then
    printf '%s%s%s\n' "${flag_colors[0]}" "${lines[0]}" "$DEF"
  else
    for i in "${!lines[@]}"; do
      local segment_index=$((i * (segments - 1) / (line_count - 1)))
      ((segment_index >= segments)) && segment_index=$((segments - 1))
      printf '%s%s%s\n' "${flag_colors[segment_index]}" "${lines[i]}" "$DEF"
    done
  fi
  [[ -n $title ]] && xecho "$title"
}

# Pre-defined banners
get_update_banner(){
  cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
}
get_clean_banner(){
  cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝
EOF
}

# Print predefined banner
# Usage: print_named_banner "update"|"clean" [title]
print_named_banner(){
  local name="$1" title="${2:-Meow (> ^ <)}" banner
  case "$name" in
  update) banner=$(get_update_banner) ;;
  clean) banner=$(get_clean_banner) ;;
  *) die "Unknown banner name: $name" ;;
  esac
  print_banner "$banner" "$title"
}

#============ Build Environment Setup ============
# Setup optimized build environment for Arch Linux
setup_build_env(){
  [[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf &>/dev/null
  # Rust optimization flags
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
  # C/C++ optimization flags
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"
  # Linker optimization flags
  export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"
  # Cargo configuration
  export
  export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
  export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_CACHE_RUSTC_INFO=1 RUSTC_BOOTSTRAP=1
  # Parallel build settings
  local nproc_count
  nproc_count=$(nproc 2>/dev/null || echo 4)
  export MAKEFLAGS="-j${nproc_count}"
  export NINJAFLAGS="-j${nproc_count}"

  # Compiler selection (prefer LLVM toolchain)
  if has clang && has clang++; then
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export NM=llvm-nm
    export RANLIB=llvm-ranlib

    # Use lld linker if available
    if has ld.lld; then
      export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
    fi
  fi

  # Initialize dbus if available
  has dbus-launch && eval "$(dbus-launch 2>/dev/null || :)"
}

#============ System Maintenance Functions ============
# Run system maintenance commands safely
run_system_maintenance(){
  local cmd=$1; shift; local args=("$@")
  has "$cmd" || return 0
  case "$cmd" in
    modprobed-db) "$cmd" store &>/dev/null || :;;
    hwclock | updatedb | chwd) run_priv "$cmd" "${args[@]}" &>/dev/null || :;;
    mandb) run_priv "$cmd" -q &>/dev/null || mandb -q &>/dev/null || :;;
    *) run_priv "$cmd" "${args[@]}" &>/dev/null || :;;
  esac
}

#============ Disk Usage Helpers ============
# Capture current disk usage
capture_disk_usage(){
  local var_name=$1; local -n ref="$var_name"
  ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}

#============ File Finding Helpers ============
# Use fd if available, fallback to find
find_files(){
  if has fd; then
    fd -H "$@"
  else
    find "$@"
  fi
}

# NUL-safe finder using fd/fdf/find
find0(){
  local root="$1"; shift
  if has fdf; then
    fdf -H -0 "$@" . "$root"
  elif has fd; then
    fd -H -0 "$@" . "$root"
  else
    find "$root" "$@" -print0
  fi
}

#============ Package Manager Detection ============
# Detect and return best available AUR helper or pacman
# Cache result to avoid repeated checks
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()
detect_pkg_manager(){
  # Return cached result if available
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

# Get package manager name only (without options)
get_pkg_manager(){
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

# Get AUR options for the detected package manager
get_aur_opts(){
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

#============ SQLite Maintenance ============
# Vacuum a single SQLite database and return bytes saved
vacuum_sqlite(){
  local db=$1 s_old s_new
  [[ -f $db ]] || { printf '0\n'; return; }
  # Skip if probably open
  [[ -f ${db}-wal || -f ${db}-journal ]] && { printf '0\n'; return; }
  # Validate it's actually a SQLite database file
  if ! head -c 16 "$db" 2>/dev/null | grep -q 'SQLite format 3'; then
    printf '0\n'; return
  fi
  s_old=$(stat -c%s "$db" 2>/dev/null) || { printf '0\n'; return; }
  # VACUUM already rebuilds indices, making REINDEX redundant
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || { printf '0\n'; return; }
  s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
  printf '%d\n' "$((s_old - s_new))"
}
# Clean SQLite databases in current working directory
clean_sqlite_dbs(){
  local total=0 db saved
  # Batch file type checks to reduce subprocess calls
  while IFS= read -r -d '' db; do
    # Skip non-regular files early
    [[ -f $db ]] || continue
    saved=$(vacuum_sqlite "$db" || printf '0')
    ((saved > 0)) && total=$((total + saved))
  done < <(find0 . -maxdepth 1 -type f)
  ((total > 0)) && printf '  %s\n' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"
}

#============ Process Management ============
# Wait for processes to exit, kill if timeout
ensure_not_running_any(){
  local timeout=6 p
  # Optimized: Use single pgrep with pattern instead of multiple calls
  local pattern=$(printf '%s|' "$@"); pattern=${pattern%|}

  # Quick check if any processes are running
  pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return

  # Show waiting message for found processes
  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &>/dev/null && printf '  %s\n' "${YLW}Waiting for ${p} to exit...${DEF}"
  done

  # Single wait loop checking all processes with one pgrep call
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return
    sleep 1
  done

  # Kill any remaining processes (single pkill call)
  if pgrep -x -u "$USER" -f "$pattern" &>/dev/null; then
    printf '  %s\n' "${RED}Killing remaining processes...${DEF}"
    pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :
    sleep 1
  fi
}

#============ Browser Profile Detection ============
# Firefox-family profile discovery
foxdir(){
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

# List all Mozilla profiles in a base directory
mozilla_profiles(){
  local base=$1 p
  declare -A seen
  [[ -d $base ]] || return 0
  # Process installs.ini using awk for efficiency
  if [[ -f $base/installs.ini ]]; then
    while IFS= read -r p; do
      [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s\n' "$base/$p"; seen[$p]=1; }
    done < <(awk -F= '/^Default=/ {print $2}' "$base/installs.ini")
  fi
  # Process profiles.ini using awk for efficiency
  if [[ -f $base/profiles.ini ]]; then
    while IFS= read -r p; do
      [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s\n' "$base/$p"; seen[$p]=1; }
    done < <(awk -F= '/^Path=/ {print $2}' "$base/profiles.ini")
  fi
}

# Chromium roots (native/flatpak/snap)
chrome_roots_for(){
  case "$1" in
    chrome) printf '%s\n' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;;
    chromium) printf '%s\n' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;;
    brave) printf '%s\n' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;;
    opera) printf '%s\n' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;;
    *) : ;;
  esac
}
# List Default + Profile * dirs under a Chromium root
chrome_profiles(){
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s\n' "$d"; done
}

#============ Path Cleaning Helpers ============
# Helper to expand wildcard paths safely
_expand_wildcards(){
  local path=$1
  local -n result_ref=$2
  if [[ $path == *\** ]]; then
    # Use globbing directly and collect existing items
    shopt -s nullglob
    # shellcheck disable=SC2206  # Intentional globbing for wildcard expansion
    local -a items=($path)
    for item in "${items[@]}"; do
      [[ -e $item ]] && result_ref+=("$item")
    done
    shopt -u nullglob
  else
    [[ -e $path ]] && result_ref+=("$path")
  fi
}

# Clean arrays of file/directory paths
clean_paths(){
  local paths=("$@") path
  # Batch check existence to reduce syscalls
  local existing_paths=()
  for path in "${paths[@]}"; do
    _expand_wildcards "$path" existing_paths
  done
  # Batch delete all existing paths at once
  [[ ${#existing_paths[@]} -gt 0 ]] && rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}
# Clean paths with privilege escalation
clean_with_sudo(){
  local paths=("$@") path
  # Batch check existence to reduce syscalls and sudo invocations
  local existing_paths=()
  for path in "${paths[@]}"; do
    _expand_wildcards "$path" existing_paths
  done
  # Batch delete all existing paths at once with single sudo call
  [[ ${#existing_paths[@]} -gt 0 ]] && run_priv rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}

#============ Download Tool Detection ============
# Get best available download tool (with optional skip for piping)
# Usage: get_download_tool [--no-aria2]
# shellcheck disable=SC2120
_DOWNLOAD_TOOL_CACHED=""
get_download_tool(){
  local skip_aria2=0
  [[ ${1:-} == --no-aria2 ]] && skip_aria2=1
  # Return cached if available and aria2 not being skipped
  if [[ -n $_DOWNLOAD_TOOL_CACHED && $skip_aria2 -eq 0 ]]; then
    printf '%s' "$_DOWNLOAD_TOOL_CACHED"; return 0
  fi
  local tool
  if [[ $skip_aria2 -eq 0 ]] && has aria2c; then
    tool=aria2c
  elif has curl; then
    tool=curl
  elif has wget2; then
    tool=wget2
  elif has wget; then
    tool=wget
  else
    return 1
  fi
  [[ $skip_aria2 -eq 0 ]] && _DOWNLOAD_TOOL_CACHED=$tool
  printf '%s' "$tool"
}
# Download a file using best available tool
# Usage: download_file <url> <output_path>
download_file(){
  local url=$1 output=$2 tool
  # shellcheck disable=SC2119
  tool=$(get_download_tool) || return 1
  case $tool in
    aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "$(dirname "$output")" -o "$(basename "$output")" "$url" ;;
    curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;;
    wget2) wget2 -q -O "$output" "$url" ;;
    wget) wget -qO "$output" "$url" ;;
    *) return 1 ;;
  esac
}
# ============ End of inlined lib/common.sh ============

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
    # Use cached package manager detection
    local pkgmgr
    pkgmgr=$(get_pkg_manager)
    run_priv "$pkgmgr" -Scc --noconfirm &>/dev/null || :
  fi
  if has apt-get; then run_priv apt-get clean &>/dev/null || :; run_priv apt-get autoclean &>/dev/null || :; fi
}

snap_flatpak_trim(){
  has flatpak && flatpak uninstall --unused --delete-data -y &>/dev/null || :
  if has snap; then
    printf '%s\n' "🔄${BLU}Removing old Snap revisions...${DEF}"
    # Remove disabled snaps (old revisions) individually with correct argument structure
    while read -r name version rev tracking publisher notes; do
      if [[ ${notes:-} == *disabled* ]]; then
        run_priv snap remove "$name" --revision "$rev" &>/dev/null || :
      fi
    done < <(snap list --all 2>/dev/null || :)
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
