#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar extglob; IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}" DEBIAN_FRONTEND=noninteractive
cd "$(cd "$( dirname "${BASH_SOURCE[0]}" )" &>/dev/null && pwd -P)" || exit 1
# apt-fuzz — optimized sk/fzf TUI for apt/nala/apt-fast on Raspberry Pi/DietPi
# Features: fuzzy search, cached previews, multi-select, backup/restore, prefetching
# ============ Inlined from lib/common.sh ============
has(){ command -v -- "$1" &>/dev/null; }
load_dietpi_globals(){ [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :; }
find_with_fallback(){
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2>/dev/null || shift $#
  if has fdf; then fdf -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"; elif has fd; then fd -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"; else
    local find_type_arg
    case "$ftype" in f) find_type_arg="-type f" ;; d) find_type_arg="-type d" ;; l) find_type_arg="-type l" ;; *) find_type_arg="-type f" ;; esac
    if [[ -n $action ]]; then find "$search_path" $find_type_arg -name "$pattern" "$action" "$@"; else find "$search_path" $find_type_arg -name "$pattern"; fi
  fi
}
# ============ End of inlined lib/common.sh ============
: "${XDG_CACHE_HOME:=${HOME}/.cache}"
CACHE_DIR="${XDG_CACHE_HOME%/}/apkg"
CACHE_INDEX="${CACHE_DIR}/.index"
: "${APT_FUZZ_CACHE_TTL:=86400}"
: "${APT_FUZZ_CACHE_MAX_BYTES:=52428800}"
: "${APT_FUZZ_PREFETCH_JOBS:=4}"
mkdir -p -- "$CACHE_DIR" &>/dev/null
trap 'ps -o pid= --ppid=$$ 2>/dev/null | xargs -r kill 2>/dev/null; exit' EXIT SIGINT SIGTERM
# Tool detection
command -v fzf &>/dev/null || exit 1
find_cache_files(){ :; }
if command -v fd &>/dev/null; then
  FIND_TOOL="fd"
  find_cache_files(){ fd -0 -d 1 -tf . "$CACHE_DIR" 2>/dev/null; }
elif command -v fdfind &>/dev/null; then
  FIND_TOOL="fdfind"
  find_cache_files(){ fdfind -0 -d 1 -tf . "$CACHE_DIR" 2>/dev/null; }
else
  FIND_TOOL="find"
  find_cache_files(){ find "$CACHE_DIR" -maxdepth 1 -type f -print0 2>/dev/null; }
fi
FINDER_OPTS=(--layout=reverse-list --no-hscroll)
[[ -n ${APT_FUZZ_FINDER_OPTS:-} ]] && read -r -a FINDER_OPTS <<< "$APT_FUZZ_FINDER_OPTS"
# Manager detection
declare -A MANAGERS=([apt]=1)
command -v nala &>/dev/null && MANAGERS[nala]=1
command -v apt-fast &>/dev/null && MANAGERS[apt - fast]=1
PRIMARY_MANAGER="${APT_FUZZ_MANAGER:-apt}"
[[ -z ${MANAGERS[$PRIMARY_MANAGER]:-} ]] && PRIMARY_MANAGER=apt-get
[[ -n ${MANAGERS[nala]:-} ]] && PRIMARY_MANAGER=nala
[[ -z ${MANAGERS[nala]:-} && -n ${MANAGERS[apt - fast]:-} ]] && PRIMARY_MANAGER=apt-fast
byte_to_human(){
  local bytes="${1:-0}" i=0 pow=1; local -a units=(B K M G T)
  while [[ $bytes -ge $((pow * 1024)) && $i -lt 4 ]]; do
    pow=$((pow * 1024)); i=$((i + 1))
  done
  local v10=$(((bytes * 10 + (pow / 2)) / pow))
  local w=$((v10 / 10)) d=$((v10 % 10))
  ((d > 0)) && printf '%d.%d%s\n' "$w" "$d" "${units[i]}" || printf '%d%s\n' "$w" "${units[i]}"
}
# Index-based cache management
_update_cache_index(){
  local tmp=$(mktemp "${CACHE_INDEX}.XXXXXX")
  find_cache_files | xargs -0 -r stat -c '%n|%s|%Y' > "$tmp" 2>/dev/null || :
  mv -f "$tmp" "$CACHE_INDEX"
}
_cache_info_from_index(){ awk -F'|' 'BEGIN{t=f=o=0}{f++;t+=$2;if(!o||$3<o)o=$3}END{print t,f,o}' "$CACHE_INDEX" 2>/dev/null || echo "0 0 0"; }
evict_old_cache(){
  [[ ! -s $CACHE_INDEX ]] && _update_cache_index
  [[ ! -s $CACHE_INDEX ]] && return
  local now=$(date +%s) limit="$APT_FUZZ_CACHE_MAX_BYTES" del cutoff valid
  cutoff=$((now - APT_FUZZ_CACHE_TTL)); del=$(mktemp); valid=$(mktemp)
  trap 'rm -f "$del" "$valid"' RETURN
  awk -F'|' -v c="$cutoff" '$3<c{print $1}' "$CACHE_INDEX" > "$del"
  awk -F'|' -v c="$cutoff" '$3>=c' "$CACHE_INDEX" > "$valid"
  if ((limit > 0)) && [[ -s $valid ]]; then
    local total=$(awk -F'|' '{s+=$2}END{print s+0}' "$valid") excess
    if ((total > limit)); then
      excess=$((total - limit)); sort -t'|' -k3,3n "$valid" | awk -F'|' -v e="$excess" 'BEGIN{d=0}d<e{print $1;d+=$2}' >> "$del"
    fi
  fi
  xargs -r -a "$del" rm -f --
  _update_cache_index
}
# Cache & preview
_cache_file_for(){ printf '%s/%s.cache' "$CACHE_DIR" "${1//[^a-zA-Z0-9._+-]/_}"; }
_generate_preview(){
  local pkg="$1" out tmp
  out="$(_cache_file_for "$pkg")"; tmp="${out}.tmp.$$"
  {
    apt-cache show "$pkg" 2>/dev/null || :
    printf '\n--- changelog (first 200 lines) ---\n'
    apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :
  } > "$tmp" 2>/dev/null
  sed -i 's/\x1b\[[0-9;]*m//g' "$tmp" 2>/dev/null || :
  mv -f "$tmp" "$out"
  chmod 644 "$out" 2>/dev/null || :
}
_cached_preview_print(){
  local pkg="$1" f now mtime
  f="$(_cache_file_for "$pkg")"
  now=$(date +%s); mtime=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
  if ((now - mtime < APT_FUZZ_CACHE_TTL)); then
    cat "$f" 2>/dev/null || echo "(no preview)"
  else
    _generate_preview "$pkg"
    cat "$f" 2>/dev/null || echo "(no preview)"
  fi
}
export -f _cached_preview_print _cache_file_for _generate_preview
# Background prefetch
_prefetch_lists(){
  (apt-cache pkgnames > "$CACHE_DIR/pkgnames.list" 2>/dev/null) &
  (dpkg-query -W -f='${Package}\n' > "$CACHE_DIR/installed.list" 2>/dev/null) &
  (apt list --upgradable 2>/dev/null | awk -F/ 'NR>1{print $1}' > "$CACHE_DIR/upgradable.list") &
}
_prefetch_previews(){
  wait; local i=0 pkg
  while IFS= read -r pkg; do
    ((i = i % APT_FUZZ_PREFETCH_JOBS, i++ == 0)) && wait
    _generate_preview "$pkg" &
  done < <(head -n 200 "$CACHE_DIR/installed.list" 2>/dev/null)
  wait; _update_cache_index
}
# Package lists
list_all_packages(){
  if [[ -f $CACHE_DIR/pkgnames.list ]]; then
    cat "$CACHE_DIR/pkgnames.list"
  else
    apt-cache pkgnames
  fi
}
list_installed(){
  if [[ -f $CACHE_DIR/installed.list ]]; then
    cat "$CACHE_DIR/installed.list"
  else
    dpkg-query -W -f='${Package}\n'
  fi
}
list_upgradable(){
  if [[ -f $CACHE_DIR/upgradable.list ]]; then
    cat "$CACHE_DIR/upgradable.list"
  else
    apt list --upgradable 2>/dev/null | awk -F/ 'NR>1{print $1}'
  fi
}
# Manager runner
run_mgr(){
  local action="$1"; shift
  local -a pkgs=("$@") cmd=()
  case "$PRIMARY_MANAGER" in
    nala)
      case "$action" in
        update|upgrade|autoremove|clean) cmd=(nala "$action" -y) ;;
        *) cmd=(nala "$action" -y "${pkgs[@]}") ;;
      esac;;
    apt-fast)
      case "$action" in
        update|upgrade|autoremove|clean) cmd=(apt-fast "$action" -y) ;;
        *) cmd=(apt-fast "$action" -y "${pkgs[@]}") ;;
      esac;;
    *)
      case "$action" in
        update|upgrade|autoremove|clean) cmd=(apt-get "$action" -y) ;;
        install | remove | purge) cmd=(apt-get "$action" -y "${pkgs[@]}") ;;
        *) cmd=(apt "$action" "${pkgs[@]}") ;;
      esac;;
  esac
  printf 'Running: sudo %s\n' "${cmd[*]}"
  sudo "${cmd[@]}"
}
choose_manager(){
  local choice=$(printf '%s\n' "${!MANAGERS[@]}" | fzf "${FINDER_OPTS[@]}" --height=12% --prompt="Manager> ")
  [[ -n $choice ]] && PRIMARY_MANAGER="$choice"
}
# UI helpers
_status_header(){
  local total files oldest age now=$(date +%s) size
  read -r total files oldest < <(_cache_info_from_index)
  ((oldest == 0)) && age="0m" || age=$(((now - oldest) / 60))m
  size=$(byte_to_human "$total")
  printf 'manager: %s | cache: %s files, %s, oldest: %s\m' "$PRIMARY_MANAGER" "$files" "$size" "$age"
}
action_menu_for_pkgs(){
  local -a pkgs=("$@") actions=(Install Remove Purge Changelog Cancel) choice
  [[ ${#pkgs[@]} -eq 0 ]] && return
  choice=$(printf '%s\n' "${actions[@]}" | fzf "${FINDER_OPTS[@]}" --height=12% --prompt="Action for ${#pkgs[@]} pkgs> ")
  [[ -z $choice ]] && return
  case "$choice" in
    Install) run_mgr install "${pkgs[@]}" ;;
    Remove) run_mgr remove "${pkgs[@]}" ;;
    Purge) run_mgr purge "${pkgs[@]}" ;;
    Changelog) for p in "${pkgs[@]}"; do apt-get changelog "$p" 2>/dev/null | less; done ;;
    Cancel) return ;;
  esac
}
menu_search(){
  local sel=$(list_all_packages | fzf "${FINDER_OPTS[@]}" \
    --multi --height=60% --prompt="Search> " --header="$(_status_header)" \
    --preview="bash -c '_cached_preview_print {}'" --preview-window=right:60% \
    --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all')
  [[ -z $sel ]] && return
  local -a pkgs
  mapfile -t pkgs <<< "$sel"
  action_menu_for_pkgs "${pkgs[@]}"
}
menu_installed(){
  local sel=$(list_installed | fzf "${FINDER_OPTS[@]}" \
    --multi --height=60% --prompt="Installed> " --header="$(_status_header)" \
    --preview="bash -c '_cached_preview_print {}'" --preview-window=right:60% \
    --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all')
  [[ -z $sel ]] && return
  local -a pkgs
  mapfile -t pkgs <<< "$sel"
  action_menu_for_pkgs "${pkgs[@]}"
}
menu_upgradable(){
  local sel=$(list_upgradable | fzf "${FINDER_OPTS[@]}" \
    --multi --height=40% --prompt="Upgradable> " --header="$(_status_header)" \
    --preview="bash -c '_cached_preview_print {}'" --preview-window=right:60% \
    --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all')
  [[ -z $sel ]] && return
  local -a pkgs
  mapfile -t pkgs <<< "$sel"
  [[ ${#pkgs[@]} -gt 0 ]] && run_mgr install "${pkgs[@]}"
}
# shellcheck disable=SC2120  # Function may be called without args (uses default)
backup_installed(){
  local out="${1:-pkglist-$(date +%F).txt}"
  dpkg-query -W -f='${Package}\n' | sort -u > "$out"
  printf 'Saved: %s\n' "$out"
}
restore_from_file(){
  local file="$1"
  [[ ! -f $file ]] && { echo "File not found: $file" >&2; return 1; }
  local -a pkgs
  mapfile -t pkgs < <(sed '/^$/d' "$file")
  [[ ${#pkgs[@]} -eq 0 ]] && { echo "No packages"; return 0; }
  local -a sel
  mapfile -t sel < <(printf '%s\n' "${pkgs[@]}" | fzf "${FINDER_OPTS[@]}" --multi --height=40% --prompt="Confirm install> ")
  [[ ${#sel[@]} -eq 0 ]] && return
  run_mgr install "${sel[@]}"
}
menu_backup_restore(){
  local -a opts=("Backup installed packages" "Restore from file" "Cancel") choice
  local header=$(_status_header)
  choice=$(printf '%s\n' "${opts[@]}" | fzf "${FINDER_OPTS[@]}" --height=12% --prompt="Backup/Restore> " --header="$header")
  [[ -z $choice ]] && return
  case "$choice" in
    "Backup installed packages") backup_installed ;;
    "Restore from file")
      read -r -p "Path: " f
      [[ -n $f ]] && restore_from_file "$f" ;;
  esac
}
menu_maintenance(){
  local -a opts=(Update Upgrade Autoremove Clean "Choose manager" Cancel) choice
  local header=$(_status_header)
  choice=$(printf '%s\n' "${opts[@]}" | fzf "${FINDER_OPTS[@]}" --height=18% --prompt="Maintenance> " --header="$header")
  [[ -z $choice ]] && return
  case "$choice" in
    Update) run_mgr update ;;
    Upgrade) run_mgr upgrade ;;
    Autoremove) run_mgr autoremove ;;
    Clean) run_mgr clean ;;
    "Choose manager") choose_manager ;;
  esac
}
main_menu(){
  evict_old_cache
  local -a menu=("Search packages" "Installed" "Upgradable" "Backup/Restore" "Maintenance" "Choose manager" "Quit") choice
  local header
  while true; do
    header=$(_status_header)
    choice=$(printf '%s\n' "${menu[@]}" | fzf "${FINDER_OPTS[@]}" --height=20% --prompt="apt-fuzz> " --header="$header")
    [[ -z $choice ]] && break
    case "$choice" in
      "Search packages") menu_search ;;
      Installed) menu_installed ;;
      Upgradable) menu_upgradable ;;
      "Backup/Restore") menu_backup_restore ;;
      Maintenance) menu_maintenance ;;
      "Choose manager") choose_manager ;;
      Quit) break ;;
    esac
  done
}
_install_self(){
  local dest="${HOME}/.local/bin/apt-fuzz" compdir="${HOME}/.local/share/bash-completion/completions"
  mkdir -p -- "${HOME}/.local/bin"
  cp -f -- "$0" "$dest"
  chmod +x -- "$dest"
  printf 'Installed: %s\n' "$dest"
  mkdir -p -- "$compdir"
  cat > "$compdir/apt-fuzz" << 'COMP'
_complete_apt_fuzz(){
  local cur="${COMP_WORDS[COMP_CWORD]}" opts="search installed upgradable install remove purge backup restore maintenance choose-manager quit"
  COMPREPLY=()
  (( COMP_CWORD==1 )) && { COMPREPLY=( $(compgen -W "$opts" -- "$cur") ); return; }
  case "${COMP_WORDS[1]}" in
    install|remove|purge)
      local pkgnames=$(apt-cache pkgnames)
      COMPREPLY=( $(compgen -W "$pkgnames" -- "$cur") ) ;;
    restore) COMPREPLY=( $(compgen -f -- "$cur") ) ;;
  esac
}
complete -F _complete_apt_fuzz apt-fuzz
COMP
  printf 'Completion: %s/apt-fuzz\n' "$compdir"
}
_uninstall_self(){
  local dest="${HOME}/.local/bin/apt-fuzz" comp="${HOME}/.local/share/bash-completion/completions/apt-fuzz"
  printf 'Uninstalling...\n'
  rm -f -- "$dest" "$comp"
  rm -rf -- "$CACHE_DIR"
  printf 'Removed: %s\n%s\n%s\n' "$dest" "$comp" "$CACHE_DIR"
}
# Entry point
if (($# > 0)); then
  case "$1" in
    --install) _install_self; exit 0;;
    --uninstall) _uninstall_self; exit 0;;
    --preview)
      [[ -z ${2:-} ]] && { echo "usage: $0 --preview <pkg>" >&2; exit 2; }
      _cached_preview_print "$2"; exit 0;;
    install | remove | purge)
      [[ $# -lt 2 ]] && { echo "Usage: $0 $1 <pkgs...>" >&2; exit 2; }
      action="$1"; shift
      run_mgr "$action" "$@"; exit 0 ;;
    help | -h | --help) printf 'Usage: %s [--install|--uninstall] | [install|remove|purge <pkgs...>]\nRun without args for TUI.\n' "$0"; exit 0;;
  esac
fi
cat << 'EOF'
apt-fuzz: sk/fzf frontend for apt/nala/apt-fast
Controls: fuzzy-search, multi-select (TAB), Enter to confirm
EOF
evict_old_cache
_prefetch_lists
_prefetch_previews &
main_menu
