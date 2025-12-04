#!/usr/bin/env bash
# Optimized: 2025-11-19 - Applied bash optimization techniques
# Source common library
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

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
has() { command -v -- "$1" &> /dev/null; }

# Echo with formatting support
xecho() { printf '%b\n' "$*"; }
# Logging functions
log() { xecho "$*"; }
die() {
  xecho "${RED}Error:${DEF} $*" >&2
  exit 1
}

# Confirmation prompt
confirm() {
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

#============ Banner Printing Functions ============
# Print banner with trans flag gradient
# Usage: print_banner "banner_text" [title]
print_banner() {
  local banner="$1" title="${2:-}"
  local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")

  # Optimized: Use read loop instead of mapfile to avoid subprocess
  local -a lines=()
  while IFS= read -r line || [[ -n $line ]]; do
    lines+=("$line")
  done <<< "$banner"

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
get_update_banner() {
  cat << 'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
}
get_clean_banner() {
  cat << 'EOF'
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
print_named_banner() {
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
setup_build_env() {
  [[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf &> /dev/null
  # Rust optimization flags
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
  # C/C++ optimization flags
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"
  # Linker optimization flags
  export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"
  # Cargo configuration
  export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
  export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_CACHE_RUSTC_INFO=1 RUSTC_BOOTSTRAP=1
  # Parallel build settings
  local nproc_count
  nproc_count=$(nproc 2> /dev/null || echo 4)
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
  has dbus-launch && eval "$(dbus-launch 2> /dev/null || :)"
}

#============ System Maintenance Functions ============
# Run system maintenance commands safely
run_system_maintenance() {
  local cmd=$1
  shift
  local args=("$@")
  has "$cmd" || return 0
  case "$cmd" in
    modprobed-db) "$cmd" store &> /dev/null || : ;;
    hwclock | updatedb | chwd) sudo "$cmd" "${args[@]}" &> /dev/null || : ;;
    mandb) sudo "$cmd" -q &> /dev/null || mandb -q &> /dev/null || : ;;
    *) sudo "$cmd" "${args[@]}" &> /dev/null || : ;;
  esac
}

#============ Disk Usage Helpers ============
# Capture current disk usage
capture_disk_usage() {
  local var_name=$1
  local -n ref="$var_name"
  ref=$(df -h --output=used,pcent / 2> /dev/null | awk 'NR==2{print $1, $2}')
}

#============ File Finding Helpers ============
# Use fd if available, fallback to find
find_files() {
  if has fd; then
    fd -H "$@"
  else
    find "$@"
  fi
}

# NUL-safe finder using fd/fdf/find
find0() {
  local root="$1"
  shift
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
detect_pkg_manager() {
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
get_pkg_manager() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager > /dev/null
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

# Get AUR options for the detected package manager
get_aur_opts() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager > /dev/null
  fi
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

#============ SQLite Maintenance ============
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
  # Use fixed-string grep (-F) for faster literal matching
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
ensure_not_running_any() {
  local timeout=6 p
  # Optimized: Use single pgrep with pattern instead of multiple calls
  local pattern=$(printf '%s|' "$@")
  pattern=${pattern%|}

  # Quick check if any processes are running
  pgrep -x -u "$USER" -f "$pattern" &> /dev/null || return

  # Show waiting message for found processes
  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &> /dev/null && printf '  %s\n' "${YLW}Waiting for ${p} to exit...${DEF}"
  done

  # Single wait loop checking all processes with one pgrep call
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &> /dev/null || return
    sleep 1
  done

  # Kill any remaining processes (single pkill call)
  if pgrep -x -u "$USER" -f "$pattern" &> /dev/null; then
    printf '  %s\n' "${RED}Killing remaining processes...${DEF}"
    pkill -KILL -x -u "$USER" -f "$pattern" &> /dev/null || :
    sleep 1
  fi
}

#============ Browser Profile Detection ============
# Firefox-family profile discovery
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

# Chromium roots (native/flatpak/snap)
chrome_roots_for() {
  case "$1" in
    chrome) printf '%s\n' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;;
    chromium) printf '%s\n' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;;
    brave) printf '%s\n' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;;
    opera) printf '%s\n' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;;
    *) : ;;
  esac
}
# List Default + Profile * dirs under a Chromium root
chrome_profiles() {
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s\n' "$d"; done
}

#============ Path Cleaning Helpers ============
# Helper to expand wildcard paths safely
_expand_wildcards() {
  local path=$1
  local -n result_ref="$2"
  if [[ $path == *\** ]]; then
    # Use globbing directly and collect existing items
    shopt -s nullglob
    # shellcheck disable=SC2206  # Intentional globbing for wildcard expansion
    local -a items=("$path")
    for item in "${items[@]}"; do
      [[ -e $item ]] && result_ref+=("$item")
    done
    shopt -u nullglob
  else
    [[ -e $path ]] && result_ref+=("$path")
  fi
}

#============ Download Tool Detection ============
# Get best available download tool (with optional skip for piping)
# Usage: get_download_tool [--no-aria2]
_DOWNLOAD_TOOL_CACHED=""
# shellcheck disable=SC2120
get_download_tool() {
  local skip_aria2=0
  [[ ${1:-} == --no-aria2 ]] && skip_aria2=1
  # Return cached if available and aria2 not being skipped
  if [[ -n $_DOWNLOAD_TOOL_CACHED && $skip_aria2 -eq 0 ]]; then
    printf '%s' "$_DOWNLOAD_TOOL_CACHED"
    return 0
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
download_file() {
  local url=$1 output=$2 tool
  # shellcheck disable=SC2119
  tool=$(get_download_tool) || return 1
  case $tool in
    aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "${output%/*}" -o "${output##*/}" "$url" ;;
    curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;;
    wget2) wget2 -q -O "$output" "$url" ;;
    wget) wget -qO "$output" "$url" ;;
    *) return 1 ;;
  esac
}

# Additional function for archmaint.sh
cleanup_pacman_lock() {
  sudo rm -f /var/lib/pacman/db.lck &> /dev/null || :
}
# ============ End of inlined lib/common.sh ============

#=========== Configuration ============
QUIET=0
VERBOSE=0
DRYRUN=0
ASSUME_YES=0
MODE=""

# Override log function to respect QUIET
log() { ((QUIET)) || xecho "$*"; }

#=========== Update Functions ===========
# Note: run_system_maintenance is now provided by common.sh

update_system_packages() {
  local pkgmgr aur_opts
  log "🔄${BLU}System update${DEF}"
  # Use cached package manager detection
  pkgmgr=$(get_pkg_manager)
  mapfile -t aur_opts < <(get_aur_opts)

  # Remove pacman lock if exists
  cleanup_pacman_lock

  # Update keyring and file databases
  sudo "$pkgmgr" -Sy archlinux-keyring --noconfirm -q &> /dev/null || :

  # Update file database only if it doesn't exist
  [[ -f /var/lib/pacman/sync/core.files ]] || sudo pacman -Fy --noconfirm &> /dev/null || :

  # Run system updates
  if [[ $pkgmgr == paru ]]; then
    local args=(--noconfirm --needed --mflags '--skipinteg --skippgpcheck'
      --bottomup --skipreview --cleanafter --removemake
      --sudoloop --sudo sudo "${aur_opts[@]}")
    log "🔄${BLU}Updating AUR packages with ${pkgmgr}...${DEF}"
    "$pkgmgr" -Suyy "${args[@]}" &> /dev/null || :
    "$pkgmgr" -Sua --devel "${args[@]}" &> /dev/null || :
  else
    log "🔄${BLU}Updating system with pacman...${DEF}"
    sudo pacman -Suyy --noconfirm --needed &> /dev/null || :
  fi
}

update_with_topgrade() {
  if has topgrade; then
    log "🔄${BLU}Running Topgrade updates...${DEF}"
    local disable_user=(--disable={config_update,system,tldr,maza,yazi,micro})
    local disable_root=(--disable={config_update,uv,pipx,yazi,micro,system,rustup,cargo,lure,shell})
    LC_ALL=C topgrade -cy --skip-notify --no-self-update --no-retry "${disable_user[@]}" &> /dev/null || :
    LC_ALL=C sudo topgrade -cy --skip-notify --no-self-update --no-retry "${disable_root[@]}" &> /dev/null || :
  fi
}

update_flatpak() {
  if has flatpak; then
    log "🔄${BLU}Updating Flatpak...${DEF}"
    sudo flatpak update -y --noninteractive --appstream &> /dev/null || :
    sudo flatpak update -y --noninteractive --system --force-remove &> /dev/null || :
  fi
}

update_rust() {
  if has rustup; then
    log "🔄${BLU}Updating Rust...${DEF}"
    rustup update
    sudo rustup update
    rustup self upgrade-data

    if has cargo; then
      log "🔄${BLU}Updating Cargo packages...${DEF}"
      local cargo_cmd=(cargo)
      for cmd in gg mommy clicker; do
        if has "cargo-$cmd"; then
          cargo_cmd=(cargo "$cmd")
          break
        fi
      done

      # Update cargo packages
      if "${cargo_cmd[@]}" install-update -Vq 2> /dev/null; then
        "${cargo_cmd[@]}" install-update -agfq
      fi
      has cargo-syu && "${cargo_cmd[@]}" syu -g
    fi
  fi
}

update_editors() {
  # Update editor plugins
  has micro && micro -plugin update &> /dev/null || :
  has yazi && ya pkg upgrade &> /dev/null || :
}

update_shells() {
  if has fish; then
    log "🔄${BLU}Updating Fish...${DEF}"
    fish -c "fish_update_completions" || :
    if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
      fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; and fisher update" || :
    elif [[ -r ${HOME}/.config/fish/functions/fisher.fish ]]; then
      fish -c ". \"$HOME/.config/fish/functions/fisher.fish\"; and fisher update" || :
    fi
  fi

  # Update basher if installed
  if [[ -d ${HOME}/.basher ]] && git -C "${HOME}/.basher" rev-parse --is-inside-work-tree &> /dev/null; then
    if git -C "${HOME}/.basher" pull --rebase --autostash --prune origin HEAD > /dev/null; then
      log "✅${GRN}Updated Basher${DEF}"
    else
      log "⚠️${YLW}Basher pull failed${DEF}"
    fi
  fi

  # Update tldr cache
  has tldr && sudo tldr -cuq || :
}

update_python() {
  if has uv; then
    log "🔄${BLU}Updating UV...${DEF}"
    uv self update -q &> /dev/null || log "⚠️${YLW}Failed to update UV${DEF}"

    log "🔄${BLU}Updating UV tools...${DEF}"
    if uv tool list -q &> /dev/null; then
      uv tool upgrade --all -q || log "⚠️${YLW}Failed to update UV tools${DEF}"
    else
      log "✅${GRN}No UV tools installed${DEF}"
    fi

    log "🔄${BLU}Updating Python packages...${DEF}"
    if has jq; then
      local pkgs
      # Optimize by only calling uv pip list once and parsing efficiently
      mapfile -t pkgs < <(uv pip list --outdated --format json 2> /dev/null | jq -r '.[].name' 2> /dev/null || :)
      if [[ ${#pkgs[@]} -gt 0 ]]; then
        # Use array expansion for better argument passing
        uv pip install -Uq --system --no-break-system-packages --compile-bytecode --refresh "${pkgs[@]}" \
          &> /dev/null || log "⚠️${YLW}Failed to update packages${DEF}"
      else
        log "✅${GRN}All Python packages are up to date${DEF}"
      fi
    else
      log "⚠️${YLW}jq not found, using fallback method${DEF}"
      # Optimize by avoiding process substitution when possible
      uv pip install --upgrade -r <(uv pip list --format freeze) &> /dev/null ||
        log "⚠️${YLW}Failed to update packages${DEF}"
    fi

    log "🔄${BLU}Updating Python interpreters...${DEF}"
    uv python update-shell -q
    uv python upgrade -q || log "⚠️${YLW}Failed to update Python versions${DEF}"
  fi
}

update_system_utils() {
  log "🔄${BLU}Running miscellaneous updates...${DEF}"
  # Pre-filter commands that exist to reduce repeated has() calls
  local cmds=(
    "fc-cache:-f"
    "update-desktop-database:"
    "update-pciids:"
    "update-smart-drivedb:"
    "update-ccache-links:"
  )

  local cmd cmd_name cmd_args
  for cmd in "${cmds[@]}"; do
    cmd_name="${cmd%%:*}"
    cmd_args="${cmd#*:}"
    if has "$cmd_name"; then
      if [[ -n $cmd_args ]]; then
        sudo "$cmd_name" "$cmd_args" &> /dev/null || :
      else
        sudo "$cmd_name" &> /dev/null || :
      fi
    fi
  done

  has update-leap && LC_ALL=C update-leap &> /dev/null || :

  # Update firmware
  if has fwupdmgr; then
    log "🔄${BLU}Updating firmware...${DEF}"
    sudo fwupdmgr refresh -y || :
    sudo fwupdtool update || :
  fi
}

update_boot() {
  log "🔍${BLU}Checking boot configuration...${DEF}"
  # Update systemd-boot if installed
  if [[ -d /sys/firmware/efi ]] && has bootctl && sudo bootctl is-installed -q &> /dev/null; then
    log "✅${GRN}systemd-boot detected, updating${DEF}"
    sudo bootctl update -q &> /dev/null
    sudo bootctl cleanup -q &> /dev/null
  else
    log "❌${YLW}systemd-boot not present, skipping${DEF}"
  fi

  # Update sdboot-manage if available
  if has sdboot-manage; then
    log "🔄${BLU}Updating sdboot-manage...${DEF}"
    sudo sdboot-manage remove &> /dev/null || :
    sudo sdboot-manage update &> /dev/null || :
  fi

  # Update initramfs
  log "🔄${BLU}Updating initramfs...${DEF}"
  if has update-initramfs; then
    sudo update-initramfs
  else
    local found_initramfs=0
    for cmd in limine-mkinitcpio mkinitcpio dracut-rebuild; do
      if has "$cmd"; then
        if [[ $cmd == mkinitcpio ]]; then
          sudo "$cmd" -P || :
        else
          sudo "$cmd" || :
        fi
        found_initramfs=1
        break
      fi
    done

    # Special case for booster
    if [[ $found_initramfs -eq 0 && -x /usr/lib/booster/regenerate_images ]]; then
      sudo /usr/lib/booster/regenerate_images || :
    elif [[ $found_initramfs -eq 0 ]]; then
      log "${YLW}No initramfs generator found, please update manually${DEF}"
    fi
  fi
}

run_update() {
  print_named_banner "update" "Meow (> ^ <)"
  setup_build_env

  checkupdates -dc &> /dev/null || :

  # Run basic system maintenance
  run_system_maintenance modprobed-db
  run_system_maintenance hwclock -w
  run_system_maintenance updatedb
  run_system_maintenance chwd -a
  run_system_maintenance mandb

  # Run update functions
  update_system_packages
  update_with_topgrade
  update_flatpak
  update_rust
  update_editors
  update_shells
  update_python
  update_system_utils
  update_boot
  log "\n${GRN}All done ✅ (> ^ <) Meow${DEF}\n"
}

#=========== Clean Functions ===========
# Note: clean_paths() and clean_with_sudo() are defined in the inlined lib/common.sh above

run_clean() {
  print_named_banner "clean"

  # Ensure sudo access
  [[ $EUID -ne 0 && -n $SUDO ]] && "$SUDO" -v

  # Capture disk usage before cleanup (using df instead of slow du -sh /)
  local disk_before disk_after
  capture_disk_usage disk_before

  log "🔄${BLU}Starting system cleanup...${DEF}"

  # Drop caches
  sync
  log "🔄${BLU}Dropping cache...${DEF}"
  sudo tee /proc/sys/vm/drop_caches &> /dev/null <<< 3

  # Store and sort modprobed database
  if has modprobed-db; then
    log "🔄${BLU}Storing kernel modules...${DEF}"
    sudo modprobed-db store

    local db_files=("${HOME}/.config/modprobed.db" "${HOME}/.local/share/modprobed.db")
    for db in "${db_files[@]}"; do
      [[ -f $db ]] && sort -u "$db" -o "$db" &> /dev/null || :
    done
  fi

  # Network cleanup
  log "🔄${BLU}Flushing network caches...${DEF}"
  has dhclient && dhclient -r &> /dev/null || :
  sudo resolvectl flush-caches &> /dev/null || :

  # Package management cleanup
  log "🔄${BLU}Removing orphaned packages...${DEF}"
  # Optimized: Use pacman directly instead of array
  local orphans_list
  orphans_list=$(pacman -Qdtq 2> /dev/null || :)
  if [[ -n $orphans_list ]]; then
    # Use xargs to pass arguments efficiently
    printf '%s\n' "$orphans_list" | xargs -r sudo pacman -Rns --noconfirm &> /dev/null || :
  fi

  log "🔄${BLU}Cleaning package cache...${DEF}"
  sudo pacman -Scc --noconfirm &> /dev/null || :
  sudo paccache -rk0 -q &> /dev/null || :

  # Python package manager cleanup
  if has uv; then
    log "🔄${BLU}Cleaning UV cache...${DEF}"
    uv cache prune -q 2> /dev/null || :
    uv cache clean -q 2> /dev/null || :
  fi

  # Cargo/Rust cleanup
  if has cargo-cache; then
    log "🔄${BLU}Cleaning Cargo cache...${DEF}"
    cargo cache -efg 2> /dev/null || :
    cargo cache -efg trim --limit 1B 2> /dev/null || :
    cargo cache -efg clean-unref 2> /dev/null || :
  fi

  # Kill CPU-intensive processes
  log "🔄${BLU}Checking for CPU-intensive processes...${DEF}"
  # Optimized: Use xargs instead of while-read loop for better performance
  ps aux --sort=-%cpu 2> /dev/null | awk 'NR>1 && $3>50.0 {print $2}' | xargs -r sudo kill -9 &> /dev/null || :

  # Reset swap
  log "🔄${BLU}Resetting swap space...${DEF}"
  sudo swapoff -a &> /dev/null || :
  sudo swapon -a &> /dev/null || :

  # Clean log files and crash dumps
  log "🔄${BLU}Cleaning logs and crash dumps...${DEF}"
  # Use fd if available, fallback to find - optimize with batch delete
  if has fd; then
    sudo fd -H -t f -e log -d 4 --changed-before 7d . /var/log -X rm &> /dev/null || :
    sudo fd -H -t f -p "core.*" -d 2 --changed-before 7d . /var/crash -X rm &> /dev/null || :
  else
    # Use -delete for better performance than -exec rm
    sudo find /var/log/ -name "*.log" -type f -mtime +7 -delete &> /dev/null || :
    sudo find /var/crash/ -name "core.*" -type f -mtime +7 -delete &> /dev/null || :
  fi
  sudo find /var/cache/apt/ -name "*.bin" -mtime +7 -delete &> /dev/null || :

  # Clean cache files
  log "🔄${BLU}Cleaning cache files...${DEF}"
  local cache_dirs=(
    "/var/cache/"
    "/tmp/"
    "/var/tmp/"
    "/var/crash/"
    "/var/lib/systemd/coredump/"
    "${HOME}/.cache/"
    "/root/.cache/"
  )

  # Clean user cache - optimize by using -delete directly with find
  if has fd; then
    # Use fd with batch delete for better performance
    fd -H -t f -d 4 --changed-before 1d . "${HOME}/.cache" -X rm &> /dev/null || :
    fd -H -t d -d 4 --changed-before 1d -E "**/.git" . "${HOME}/.cache" -X rmdir &> /dev/null || :
  else
    # find -delete is more efficient than -exec rm
    find "${HOME}/.cache" -type f -mtime +1 -delete &> /dev/null || :
    find "${HOME}/.cache" -type d -empty -delete &> /dev/null || :
  fi

  sudo systemd-tmpfiles --clean &> /dev/null || :

  # Clean system and user cache directories
  clean_with_sudo "${cache_dirs[@]/%/*}"

  # Clean Flatpak application caches
  clean_paths "${HOME}/.var/app/"*/cache/* 2> /dev/null || :

  # Clean Qt cache files
  clean_paths "${HOME}/.config/Trolltech.conf" 2> /dev/null || :

  # Rebuild KDE cache if present
  has kbuildsycoca6 && kbuildsycoca6 --noincremental &> /dev/null || :

  # Empty trash directories
  log "🔄${BLU}Emptying trash...${DEF}"
  local trash_dirs=(
    "${HOME}/.local/share/Trash/"
    "/root/.local/share/Trash/"
  )
  clean_paths "${trash_dirs[@]/%/*}" 2> /dev/null || :

  # Flatpak cleanup
  if has flatpak; then
    log "🔄${BLU}Cleaning Flatpak...${DEF}"
    flatpak uninstall --unused --delete-data -y --noninteractive &> /dev/null || :

    # Clean flatpak caches
    local flatpak_dirs=(
      "/var/tmp/flatpak-cache-"
      "${HOME}/.cache/flatpak/system-cache/"
      "${HOME}/.local/share/flatpak/system-cache/"
      "${HOME}/.var/app/*/data/Trash/"
    )
    clean_paths "${flatpak_dirs[@]}" 2> /dev/null || :
  fi

  # Clear thumbnails
  clean_paths "${HOME}/.thumbnails/" 2> /dev/null || :

  # Clean system logs
  log "🔄${BLU}Cleaning system logs...${DEF}"
  sudo rm -f --preserve-root -- /var/log/pacman.log &> /dev/null || :
  sudo journalctl --rotate --vacuum-size=1 --flush --sync -q &> /dev/null || :
  clean_with_sudo /run/log/journal/* /var/log/journal/* /root/.local/share/zeitgeist/* /home/*/.local/share/zeitgeist/* 2> /dev/null || :

  # Clean history files
  log "🔄${BLU}Cleaning history files...${DEF}"
  local history_files=(
    "${HOME}/.wget-hsts"
    "${HOME}/.curl-hsts"
    "${HOME}/.lesshst"
    "${HOME}/nohup.out"
    "${HOME}/token"
    "${HOME}/.local/share/fish/fish_history"
    "${HOME}/.config/fish/fish_history"
    "${HOME}/.zsh_history"
    "${HOME}/.bash_history"
    "${HOME}/.history"
  )

  local root_history_files=(
    "/root/.local/share/fish/fish_history"
    "/root/.config/fish/fish_history"
    "/root/.zsh_history"
    "/root/.bash_history"
    "/root/.history"
  )

  clean_paths "${history_files[@]}" 2> /dev/null || :
  clean_with_sudo "${root_history_files[@]}" 2> /dev/null || :

  # Application-specific cleanups
  log "🔄${BLU}Cleaning application caches...${DEF}"

  # LibreOffice
  local libreoffice_paths=(
    "${HOME}/.config/libreoffice/4/user/registrymodifications.xcu"
    "${HOME}/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu"
    "${HOME}/snap/libreoffice/*/.config/libreoffice/4/user/registrymodifications.xcu"
  )
  clean_paths "${libreoffice_paths[@]}" 2> /dev/null || :

  # Steam
  local steam_paths=(
    "${HOME}/.local/share/Steam/appcache/"
    "${HOME}/snap/steam/common/.cache/"
    "${HOME}/snap/steam/common/.local/share/Steam/appcache/"
    "${HOME}/.var/app/com.valvesoftware.Steam/cache/"
    "${HOME}/.var/app/com.valvesoftware.Steam/data/Steam/appcache/"
  )
  clean_paths "${steam_paths[@]/%/*}" 2> /dev/null || :

  # Optimized: Run independent cleanup tasks in parallel for better performance
  log "🔄${BLU}Cleaning applications (parallel)...${DEF}"

  # NVIDIA cleanup (background)
  { sudo rm -rf --preserve-root -- "${HOME}/.nv/ComputeCache/"* &> /dev/null || :; } &

  # Python history (background)
  {
    local python_history="${HOME}/.python_history"
    [[ ! -f $python_history ]] && { touch "$python_history" 2> /dev/null || :; }
    sudo chattr +i "$(realpath "$python_history")" &> /dev/null || :
  } &

  # Firefox cleanup (background)
  {
    local firefox_paths=(
      "${HOME}/.mozilla/firefox/*/bookmarkbackups"
      "${HOME}/.mozilla/firefox/*/saved-telemetry-pings"
      "${HOME}/.mozilla/firefox/*/sessionstore-logs"
      "${HOME}/.mozilla/firefox/*/sessionstore-backups"
      "${HOME}/.cache/mozilla/"
      "${HOME}/.var/app/org.mozilla.firefox/cache/"
      "${HOME}/snap/firefox/common/.cache/"
    )
    clean_paths "${firefox_paths[@]}" 2> /dev/null || :
    # Firefox crashes cleanup using find (no Python overhead)
    [[ -d "${HOME}/.mozilla/firefox" ]] &&
      find "${HOME}/.mozilla/firefox" -type d -name 'crashes' -exec find {} -type f -delete \; 2> /dev/null || :
  } &

  # Wine cleanup (background)
  {
    local wine_paths=(
      "${HOME}/.wine/drive_c/windows/temp/"
      "${HOME}/.cache/wine/"
      "${HOME}/.cache/winetricks/"
    )
    clean_paths "${wine_paths[@]/%/*}" 2> /dev/null || :
  } &

  # GTK recent files (background)
  {
    local gtk_paths=(
      "/.recently-used.xbel"
      "${HOME}/.local/share/recently-used.xbel"
      "${HOME}/snap/*/*/.local/share/recently-used.xbel"
      "${HOME}/.var/app/*/data/recently-used.xbel"
    )
    clean_paths "${gtk_paths[@]}" 2> /dev/null || :
  } &

  # KDE recent files (background)
  {
    local kde_paths=(
      "${HOME}/.local/share/RecentDocuments/*.desktop"
      "${HOME}/.kde/share/apps/RecentDocuments/*.desktop"
      "${HOME}/.kde4/share/apps/RecentDocuments/*.desktop"
      "${HOME}/.var/app/*/data/*.desktop"
    )
    clean_paths "${kde_paths[@]}" 2> /dev/null || :
  } &

  # Wait for all parallel cleanup tasks to complete
  wait

  # Trim disks
  log "🔄${BLU}Trimming disks...${DEF}"
  sudo fstrim -a --quiet-unsupported &> /dev/null || :
  sudo fstrim -A --quiet-unsupported &> /dev/null || :

  # Rebuild font cache
  log "🔄${BLU}Rebuilding font cache...${DEF}"
  sudo fc-cache -f &> /dev/null || :

  # SDK cleanup
  has sdk && sdk flush tmp &> /dev/null || :

  # BleachBit if available
  if has bleachbit; then
    log "🔄${BLU}Running BleachBit...${DEF}"
    LC_ALL=C LANG=C bleachbit -c --preset &> /dev/null || :

    # Run with elevated privileges if possible
    if has xhost; then
      xhost si:localuser:root &> /dev/null || :
      xhost si:localuser:"$USER" &> /dev/null || :
      LC_ALL=C LANG=C sudo bleachbit -c --preset &> /dev/null || :
    elif has pkexec; then
      LC_ALL=C LANG=C pkexec bleachbit -c --preset &> /dev/null || :
    else
      log "⚠️${YLW}Cannot run BleachBit with elevated privileges${DEF}"
    fi
  fi

  # Show disk usage results
  log "${GRN}System cleaned!${DEF}"
  capture_disk_usage disk_after

  log "==> ${BLU}Disk usage before cleanup:${DEF} ${disk_before}"
  log "==> ${GRN}Disk usage after cleanup: ${DEF} ${disk_after}"
}

#=========== Traps & Cleanup ===========
# Enhanced cleanup for archmaint
cleanup_archmaint() {
  cleanup_pacman_lock
  # Reset environment variables
  unset LC_ALL RUSTFLAGS CFLAGS CXXFLAGS LDFLAGS
}

trap cleanup_archmaint EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#=========== CLI Interface =============
show_usage() {
  cat << EOF
Usage: ${0##*/} [OPTIONS] COMMAND

Arch Linux system maintenance script for updating and cleaning.

Commands:
  update    Update system packages and components
  clean     Clean system caches and temporary files

Options:
  -h, --help       Show this help message
  -q, --quiet      Suppress normal output
  -v, --verbose    Enable verbose output
  -y, --yes        Answer yes to all prompts
  -n, --dry-run    Show what would be done without making changes

Examples:
  ${0##*/} update         # Update system packages and components
  ${0##*/} clean          # Clean system caches and temporary files
  ${0##*/} -y clean       # Clean without prompting
  ${0##*/} -qn update     # Quiet dry-run update
EOF
}

parse_args() {
  # Process options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        show_usage exit 0
        ;;
      -q | --quiet) QUIET=1 shift ;;
      -v | --verbose) VERBOSE=1 shift ;;
      -y | --yes) ASSUME_YES=1 shift ;;
      -n | --dry-run) DRYRUN=1 shift ;;
      update | clean)
        [[ -n $MODE ]] && die "Cannot specify multiple commands: $MODE and $1"
        MODE=$1 shift
        ;;
      *) die "Unknown option: $1\nUse --help for usage information." ;;
    esac
  done
  # Validate command
  if [[ -z $MODE ]]; then
    die "No command specified. Use 'update' or 'clean'.\nUse --help for usage information."
  fi
}

#=========== Main Function =============
main() {
  parse_args "$@"
  if [[ $DRYRUN -eq 1 ]]; then
    log "${YLW}Running in dry-run mode. No changes will be made.${DEF}"
  fi
  case "$MODE" in
    update) run_update ;;
    clean) run_clean ;;
    *) die "Unknown command: $MODE" ;;
  esac
}
main "$@"
