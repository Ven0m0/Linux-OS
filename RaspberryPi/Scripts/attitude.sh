#!/usr/bin/env bash
# apt-fuzz — compact fzf TUI for apt / nala / apt-fast
# Optimized for performance on resource-constrained devices like Raspberry Pi.
set -euo pipefail; shopt -s nullglob globstar

# Configuration & Environment
export LC_ALL=C LANG=C
: "${SHELL:=${BASH:-/bin/bash}}"
: "${HOME:=$(getent passwd "$USER" | cut -d: -f6)}"
: "${XDG_CACHE_HOME:=${HOME}/.cache}"

# Script-specific variables
CACHE_DIR="${XDG_CACHE_HOME%/}/apt-fuzz"
CACHE_INDEX="${CACHE_DIR}/.index"
: "${APT_FUZZ_CACHE_TTL:=86400}"          # 86400s = 1 day
: "${APT_FUZZ_CACHE_MAX_BYTES:=52428800}" # Default cache limit: 50 MiB
: "${APT_FUZZ_ANSI:=1}"
: "${APT_FUZZ_PREFETCH_JOBS:=4}"          # Concurrent jobs for prefetching previews

# Create cache directory if it doesn't exist
mkdir -p -- "$CACHE_DIR" &>/dev/null || :

# Cleanup trap
# Ensures temporary files and background jobs are cleaned up on exit.
trap 'cleanup' EXIT SIGINT SIGTERM
cleanup(){
  # Terminate any running background jobs spawned by this script
  # shellcheck disable=SC2009
  ps -o pid= --ppid=$$ | xargs kill 2>/dev/null || :
  exit 0
}

# Tool Detection (fzf/sk, fd/find)
if command -v fzf &>/dev/null; then
  FINDER=fzf
elif command -v sk &>/dev/null; then
  FINDER=sk
else
  echo "Error: fzf or skim (sk) is required." >&2; exit 1
fi

# Define a function to find files; its implementation will be the best tool available.
find_cache_files(){ :; } # Default to no-op

if command -v fd &>/dev/null; then
  find_cache_files(){ fd --hidden --type f --max-depth 1 . "$CACHE_DIR" -0; }
elif command -v fdfind &>/dev/null; then
  find_cache_files(){ fdfind --hidden --type f --max-depth 1 . "$CACHE_DIR" -0; }
else
  find_cache_files(){ find "$CACHE_DIR" -maxdepth 1 -type f -print0; }
fi

# Finder (fzf/sk) Options
FINDER_OPTS=(--layout=reverse --height=35% --tiebreak=index --no-sort --no-hscroll)
[[ "$APT_FUZZ_ANSI" -eq 1 ]] && FINDER_OPTS+=(--ansi)
# Allow user to override default options completely
[[ -n ${APT_FUZZ_FINDER_OPTS:-} ]] && read -r -a FINDER_OPTS <<< "$APT_FUZZ_FINDER_OPTS"

# Package Manager Detection (apt, nala, apt-fast)
declare -A MANAGERS
[[ -x "$(command -v nala)" ]] && MANAGERS[nala]=1
[[ -x "$(command -v apt-fast)" ]] && MANAGERS[apt-fast]=1
MANAGERS[apt]=1 # apt is always a fallback

# Determine the best default manager
PRIMARY_MANAGER="${APT_FUZZ_MANAGER:-}"
if [[ -z $PRIMARY_MANAGER ]]; then
  if [[ -n ${MANAGERS[nala]} ]]; then PRIMARY_MANAGER=nala
  elif [[ -n ${MANAGERS[apt-fast]} ]]; then PRIMARY_MANAGER=apt-fast
  else PRIMARY_MANAGER=apt; fi
fi

# Utilities
byte_to_human(){
  local bytes="${1:-0}" i=0
  local -a units=(B K M G T)
  while (( bytes >= 1024 && i < 4 )); do
    bytes=$(( bytes / 1024 )); i=$(( i + 1 ))
  done
  printf '%s%s' "$bytes" "${units[i]}"
}

# Optimized Cache Indexing & Eviction
# Creates a single index file of all cache entries (path|size|mtime)
_update_cache_index(){
  local tmp_index; tmp_index=$(mktemp "${CACHE_INDEX}.XXXXXX")
  # Use our function to get a null-delimited list of files, then stat them.
  find_cache_files 2>/dev/null | xargs -0 -r stat -c '%n|%s|%Y' > "$tmp_index" 2>/dev/null || :
  # Atomically replace the old index
  mv -f "$tmp_index" "$CACHE_INDEX"
}

# Reads cache stats directly from the index file. Very fast.
_cache_info_from_index(){
  awk -F'|' '
    BEGIN { total=0; files=0; oldest=0 }
    { files++; total+=$2; if(oldest==0 || $3<oldest) oldest=$3 }
    END { print total, files, oldest }
  ' "$CACHE_INDEX" 2>/dev/null || echo "0 0 0"
}

# Evicts old cache files based on TTL and max size.
# This implementation uses `sort` and `xargs` for optimal performance.
evict_old_cache(){
    # Don't proceed if the index doesn't exist or is empty
    [[ ! -s $CACHE_INDEX ]] && _update_cache_index
    [[ ! -s $CACHE_INDEX ]] && return

    local cutoff=$(( $(date +%s) - APT_FUZZ_CACHE_TTL ))
    local limit="$APT_FUZZ_CACHE_MAX_BYTES"
    local to_delete_tmp; to_delete_tmp=$(mktemp)
    local valid_files_tmp; valid_files_tmp=$(mktemp)

    # Defer cleanup of temp files for this function's scope
    trap 'rm -f "$to_delete_tmp" "$valid_files_tmp"' RETURN

    # Step 1: Find TTL-expired files and add their paths to the delete list
    awk -F'|' -v cutoff="$cutoff" '$3 < cutoff {print $1}' "$CACHE_INDEX" > "$to_delete_tmp"

    # Step 2: Create a temporary index of files *not* expired by TTL
    awk -F'|' -v cutoff="$cutoff" '$3 >= cutoff' "$CACHE_INDEX" > "$valid_files_tmp"

    # Step 3: If size limit is enabled and we have valid files, check total size
    if (( limit > 0 && -s "$valid_files_tmp" )); then
        local total_size
        total_size=$(awk -F'|' '{s+=$2} END{print s+0}' "$valid_files_tmp")

        # If total size is over the limit...
        if (( total_size > limit )); then
            local excess_size=$(( total_size - limit ))
            # ...sort valid files by date (oldest first) and add enough to the
            # delete list to get back under the size limit.
            sort -t'|' -k3,3n "$valid_files_tmp" | awk -F'|' -v excess="$excess_size" '
                BEGIN { deleted_sum=0 }
                deleted_sum < excess {
                    print $1;
                    deleted_sum+=$2;
                }
            ' >> "$to_delete_tmp"
        fi
    fi

    # Step 4: Perform the deletion of all identified files in a single command
    xargs -r -a "$to_delete_tmp" rm -f --

    # Step 5: Update the index once at the very end
    _update_cache_index
}

# Cached Preview Generation
_cache_file_for(){ printf '%s/%s.cache' "$CACHE_DIR" "${1//[^a-zA-Z0-9._+-]/_}"; }

_generate_preview(){
  local pkg="$1" out tmp
  out="$(_cache_file_for "$pkg")"
  tmp="${out}.tmp.$$"
  {
    apt-cache show "$pkg"
    printf '\n--- changelog (first 100 lines) ---\n'
    apt-get changelog "$pkg" 2>/dev/null | sed 100q
  } > "$tmp" 2>/dev/null
  # Strip ANSI color codes
  sed -i 's/\x1b\[[0-9;]*m//g' "$tmp" &>/dev/null || :
  mv -f "$tmp" "$out"
}

_cached_preview_print(){
  local pkg="$1" f f_mtime now
  f="$(_cache_file_for "$pkg")"
  now=$(date +%s)
  f_mtime=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)

  if (( now - f_mtime < APT_FUZZ_CACHE_TTL )); then
    cat "$f" 2>/dev/null || echo "No preview available for $pkg"
  else
    _generate_preview "$pkg"
    cat "$f" 2>/dev/null || echo "No preview available for $pkg"
  fi
}
export -f _cached_preview_print _cache_file_for _generate_preview

# Background Prefetching (for speed)
# Caches package lists in the background when the script starts.
_prefetch_package_lists(){
  ( apt-cache pkgnames > "$CACHE_DIR/pkgnames.list" 2>/dev/null ) &
  ( dpkg-query -W -f='${Package}\n' > "$CACHE_DIR/installed.list" 2>/dev/null ) &
  ( apt list --upgradable 2>/dev/null | awk -F/ 'NR>1{print $1}' > "$CACHE_DIR/upgradable.list" 2>/dev/null ) &
}

# Pre-generates previews for installed packages to make browsing faster.
_prefetch_package_previews(){
  # Wait for the installed list to be generated first
  wait
  local pkg i=0
  while IFS= read -r pkg; do
    # Run up to N jobs in parallel
    (( i=i%APT_FUZZ_PREFETCH_JOBS, i++==0 )) && wait
    _generate_preview "$pkg" &
  done < <(head -n 200 "$CACHE_DIR/installed.list") # Limit to first 200 installed packages
  wait
  _update_cache_index
}

# Package List Functions (reads from cache first)
list_all_packages(){ cat "$CACHE_DIR/pkgnames.list" 2>/dev/null || apt-cache pkgnames; }
list_installed(){ cat "$CACHE_DIR/installed.list" 2>/dev/null || dpkg-query -W -f='${Package}\n'; }
list_upgradable(){ cat "$CACHE_DIR/upgradable.list" 2>/dev/null || (apt list --upgradable 2>/dev/null | awk -F/ 'NR>1{print $1}'); }

# Manager Runner & UI Menus
run_mgr(){
  local action="$1"; shift || :
  local -a pkgs=("$@") cmd=()
  case "$PRIMARY_MANAGER" in
    nala) cmd=(nala "$action" -y "${pkgs[@]}") ;;
    apt-fast) cmd=(apt-fast "$action" -y "${pkgs[@]}") ;;
    *) cmd=(apt-get "$action" -y "${pkgs[@]}") ;;
  esac
  printf '\nRunning: \e[1;32msudo %s\e[0m\n' "${cmd[*]}"
  sudo "${cmd[@]}"
}

_status_header(){
  local total files oldest age size
  read -r total files oldest < <(_cache_info_from_index)
  if (( oldest == 0 )); then age="0m"; else age=$(( ($(date +%s) - oldest) / 60 ))m; fi
  size=$(byte_to_human "$total")
  printf 'Manager: %s | Cache: %s files, %s, oldest: %s' "$PRIMARY_MANAGER" "$files" "$size" "$age"
}

action_menu_for_pkgs(){
  local -a pkgs=("$@") choice
  [[ ${#pkgs[@]} -eq 0 ]] && return
  local prompt="Action for ${#pkgs[@]} pkg(s)> "
  choice=$(printf 'Install\nRemove\nPurge\nChangelog\nCancel' | "$FINDER" "${FINDER_OPTS[@]}" --height=25% --prompt="$prompt")
  case "$choice" in
    Install) run_mgr install "${pkgs[@]}" ;;
    Remove) run_mgr remove "${pkgs[@]}" ;;
    Purge) run_mgr purge "${pkgs[@]}" ;;
    Changelog) less < <(for pkg in "${pkgs[@]}"; do apt-get changelog "$pkg"; done) ;;
    *) return ;;
  esac
}

menu_search(){
  local -a pkgs
  mapfile -t pkgs < <(list_all_packages | "$FINDER" "${FINDER_OPTS[@]}" --height=70% --multi --prompt="Search> " \
    --header="$(_status_header)" --preview="bash -c '_cached_preview_print {}'")
  action_menu_for_pkgs "${pkgs[@]}"
}

menu_installed(){
  local -a pkgs
  mapfile -t pkgs < <(list_installed | "$FINDER" "${FINDER_OPTS[@]}" --height=70% --multi --prompt="Installed> " \
    --header="$(_status_header)" --preview="bash -c '_cached_preview_print {}'")
  action_menu_for_pkgs "${pkgs[@]}"
}

menu_upgradable(){
  local -a pkgs
  mapfile -t pkgs < <(list_upgradable | "$FINDER" "${FINDER_OPTS[@]}" --height=50% --multi --prompt="Upgradable> " \
    --header="$(_status_header)" --preview="bash -c '_cached_preview_print {}'")
  [[ ${#pkgs[@]} -gt 0 ]] && run_mgr install "${pkgs[@]}"
}

menu_maintenance(){
  local choice
  choice=$(printf 'Update\nUpgrade All\nAutoremove\nClean' | "$FINDER" "${FINDER_OPTS[@]}" --prompt="Maintenance> ")
  case "$choice" in
    Update) run_mgr update ;;
    "Upgrade All") run_mgr upgrade ;;
    Autoremove) run_mgr autoremove ;;
    Clean) run_mgr clean ;;
  esac
}

choose_manager(){
  local choice
  choice=$(printf '%s\n' "${!MANAGERS[@]}" | "$FINDER" "${FINDER_OPTS[@]}" --height=20% --prompt="Select Manager> ")
  [[ -n $choice ]] && PRIMARY_MANAGER="$choice"
}

# Main TUI Loop
main_menu(){
  local choice
  while true; do
    choice=$(printf 'Search\nInstalled\nUpgradable\nMaintenance\nChange Manager\nQuit' \
      | "$FINDER" "${FINDER_OPTS[@]}" --height=40% --prompt="apt-fuzz> " --header="$(_status_header)")

    case "$choice" in
      Search) menu_search ;;
      Installed) menu_installed ;;
      Upgradable) menu_upgradable ;;
      Maintenance) menu_maintenance ;;
      "Change Manager") choose_manager ;;
      Quit|"") break ;;
    esac
  done
}

# Entry Point & CLI Commands

# Kick off background tasks immediately
evict_old_cache
_prefetch_package_lists
_prefetch_package_previews & # Fork preview generation

# Handle non-interactive commands
if (( $# > 0 )); then
  case "$1" in
    install|remove|purge)
      cmd="$1"; shift
      [[ $# -eq 0 ]] && { echo "Error: No packages specified for action '$cmd'." >&2; exit 1; }
      run_mgr "$cmd" "$@"
      ;;
    *)
      echo "Unknown command: $1" >&2
      echo "Usage: $0 [install|remove|purge] [package...]" >&2
      exit 1
      ;;
  esac
  exit 0
fi

# Start the main interactive TUI
main_menu
