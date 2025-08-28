#!/usr/bin/env bash
# apt-parus — sk-preferred fzf/sk TUI for apt/nala/apt-fast
# - preview cache at ${XDG_CACHE_HOME:-$HOME/.cache}/apt-parus
# - TTL via APT_PARUS_CACHE_TTL (default 86400)
# - optional max cache size via APT_PARUS_CACHE_MAX_BYTES (0 disables)
# - install: --install (drops script to ~/.local/bin and user bash completion)
# style: [[ ... ]], 2-space indentation, use &>/dev/null || :

set -euo pipefail
shopt -s nullglob globstar

export LC_ALL=C LANG=C
: "${SHELL:=/bin/bash}"
: "${XDG_CACHE_HOME:=${HOME:-$HOME}/.cache}"
CACHE_DIR="${XDG_CACHE_HOME%/}/apt-parus"
mkdir -p "$CACHE_DIR"
: "${APT_PARUS_CACHE_TTL:=86400}"
: "${APT_PARUS_CACHE_MAX_BYTES:=0}"

# prefer skim/sk over fzf
if command -v sk &>/dev/null || :; then
  FINDER=sk
elif command -v fzf &>/dev/null || :; then
  FINDER=fzf
else
  echo "Please install skim (sk) or fzf." >&2
  exit 1
fi

# managers
HAS_NALA=0; HAS_APT_FAST=0
command -v nala &>/dev/null && HAS_NALA=1 || :
command -v apt-fast &>/dev/null && HAS_APT_FAST=1 || :
PRIMARY_MANAGER=apt
[[ $HAS_NALA -eq 1 ]] && PRIMARY_MANAGER=nala
[[ $HAS_NALA -eq 0 && $HAS_APT_FAST -eq 1 ]] && PRIMARY_MANAGER=apt-fast

# -------------------------
# Cache helpers
# -------------------------
_cache_file_for() {
  local pkg="$1"
  printf '%s/%s.cache' "$CACHE_DIR" "${pkg//[^a-zA-Z0-9._+-]/_}"
}
_cache_mins() { printf '%d' $(( (APT_PARUS_CACHE_TTL + 59) / 60 )); }

evict_old_cache() {
  local mmin; mmin="$(_cache_mins)"
  find "$CACHE_DIR" -maxdepth 1 -type f -mmin +"$mmin" -delete &>/dev/null || :
  if [[ ${APT_PARUS_CACHE_MAX_BYTES:-0} -gt 0 ]]; then
    local total; total=$(du -sb "$CACHE_DIR" 2>/dev/null | awk '{print $1}' 2>/dev/null || echo 0)
    if [[ $total -gt $APT_PARUS_CACHE_MAX_BYTES ]]; then
      while IFS= read -r -d '' entry; do
        file="${entry#* }"
        rm -f "$file" &>/dev/null || :
        total=$(du -sb "$CACHE_DIR" 2>/dev/null | awk '{print $1}' 2>/dev/null || echo 0)
        [[ $total -le $APT_PARUS_CACHE_MAX_BYTES ]] && break
      done < <(find "$CACHE_DIR" -maxdepth 1 -type f -printf '%T@ %p\0' | tr '\0' '\n' | sort -n | sed -n '1,100p' | tr '\n' '\0')
    fi
  fi
}

_cache_stats() {
  local files size oldest age
  files=$(find "$CACHE_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
  size=$(du -sb "$CACHE_DIR" 2>/dev/null | awk '{print $1}' 2>/dev/null || echo 0)
  oldest=$(find "$CACHE_DIR" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -n1 | awk '{print $1}')
  if [[ -z $oldest ]]; then
    age="0m"
  else
    age=$(( ( $(date +%s) - ${oldest%%.*} ) / 60 ))m
  fi
  printf '%s|%s|%s' "$files" "$size" "$age"
}

# -------------------------
# Preview (atomic)
# -------------------------
_generate_preview() {
  local pkg="$1" out tmp
  out="$(_cache_file_for "$pkg")"
  tmp="${out}.$$.$RANDOM.tmp"
  {
    apt-cache show "$pkg" 2>/dev/null || :
    printf '\n--- changelog (first 200 lines) ---\n'
    command -v apt-get &>/dev/null && apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :
  } >"$tmp" 2>/dev/null || :
  sed -i 's/\x1b\[[0-9;]*m//g' "$tmp" &>/dev/null || :
  mv -f "$tmp" "$out"
  chmod 644 "$out" &>/dev/null || :
}

_cached_preview_print() {
  local pkg="$1" f
  evict_old_cache
  f="$(_cache_file_for "$pkg")"
  if [[ -f $f && $(( $(date +%s) - $(stat -c %Y -- "$f") )) -lt APT_PARUS_CACHE_TTL ]]; then
    cat "$f"
  else
    _generate_preview "$pkg"
    cat "$f" 2>/dev/null || echo "(no preview)"
  fi
}
export -f _cached_preview_print

# -------------------------
# Manager runner (apt-get for apt)
# -------------------------
run_mgr() {
  local action="$1"; shift || :
  local pkgs=("$@"); local cmd=()
  case "$PRIMARY_MANAGER" in
    nala)
      case "$action" in
        update) cmd=(nala update) ;;
        upgrade) cmd=(nala upgrade -y) ;;
        autoremove) cmd=(nala autoremove -y) ;;
        clean) cmd=(nala clean) ;;
        *) cmd=(nala "$action" -y "${pkgs[@]}") ;;
      esac ;;
    apt-fast)
      case "$action" in
        update) cmd=(apt-fast update) ;;
        upgrade) cmd=(apt-fast upgrade -y) ;;
        autoremove) cmd=(apt-fast autoremove -y) ;;
        clean) cmd=(apt-fast clean) ;;
        *) cmd=(apt-fast "$action" -y "${pkgs[@]}") ;;
      esac ;;
    *)
      case "$action" in
        update) cmd=(apt-get update) ;;
        upgrade) cmd=(apt-get upgrade -y) ;;
        install) cmd=(apt-get install -y "${pkgs[@]}") ;;
        remove) cmd=(apt-get remove -y "${pkgs[@]}") ;;
        purge) cmd=(apt-get purge -y "${pkgs[@]}") ;;
        autoremove) cmd=(apt-get autoremove -y) ;;
        clean) cmd=(apt-get clean) ;;
        *) cmd=(apt "$action" "${pkgs[@]}") ;;
      esac ;;
  esac
  printf 'Running: sudo %s\n' "${cmd[*]}"
  sudo "${cmd[@]}"
}

choose_manager() {
  local opts=("apt"); [[ $HAS_NALA -eq 1 ]] && opts+=("nala"); [[ $HAS_APT_FAST -eq 1 ]] && opts+=("apt-fast")
  local choice; choice=$(printf '%s\n' "${opts[@]}" | $FINDER --height=12% --reverse --prompt="Manager> ")
  [[ -n $choice ]] && PRIMARY_MANAGER="$choice"
}

# -------------------------
# Lists, helpers, UI
# -------------------------
list_all_packages() { apt-cache search . 2>/dev/null | sed -E 's/ - /|/; s/\t/ /g'; }
list_installed()     { dpkg-query -W -f='${binary:Package}|${Version}\n' 2>/dev/null || :; }
list_upgradable()    { apt list --upgradable 2>/dev/null | awk -F'/' 'NR>1{print $1}'; }
backup_installed()   { local out="${1:-pkglist-$(date +%F).txt}"; dpkg-query -W -f='${binary:Package}\n' | sort -u >"$out"; printf 'Saved: %s\n' "$out"; }
restore_from_file()  {
  local file="$1"; [[ ! -f $file ]] && { echo "File not found: $file" >&2; return 1; }
  mapfile -t pkgs < <(sed '/^$/d' "$file"); [[ ${#pkgs[@]} -eq 0 ]] && { echo "No packages."; return 0; }
  mapfile -t sel < <(printf '%s\n' "${pkgs[@]}" | $FINDER --multi --height=40% --reverse --prompt="Confirm install> ")
  [[ ${#sel[@]} -eq 0 ]] && return; run_mgr install "${sel[@]}"
}
show_changelog() { local pkg="$1"; command -v apt-get &>/dev/null && (apt-get changelog "$pkg" 2>/dev/null || echo "No changelog for $pkg") || echo "apt-get unavailable"; }

action_menu_for_pkgs() {
  local pkgs=("$@"); local actions=("Install" "Remove" "Purge" "Changelog" "Cancel")
  local act; act=$(printf '%s\n' "${actions[@]}" | $FINDER --height=12% --reverse --prompt="Action for ${#pkgs[@]} pkgs> ")
  [[ -z $act ]] && return
  case "$act" in
    Install) run_mgr install "${pkgs[@]}" ;;
    Remove) run_mgr remove "${pkgs[@]}" ;;
    Purge) run_mgr purge "${pkgs[@]}" ;;
    Changelog) for p in "${pkgs[@]}"; do show_changelog "$p"; read -r -p "Enter to continue..." || :; done ;;
    Cancel) return ;;
  esac
}

_status_header() {
  local s stats files size age human
  stats=$(_cache_stats)
  IFS='|' read -r files size age <<< "$stats"
  human=$(awk -v b="$size" 'function h(s){split("B K M G T",u); for(i=0;s>=1024 && i<4;i++) s/=1024; return sprintf("%.1f%s",s,u[i+1])} END{print h(b)}')
  printf 'manager: %s | cache: %s files, %s, oldest: %s' "$PRIMARY_MANAGER" "$files" "$human" "$age"
}

menu_search_packages() {
  local header sel; header="$(_status_header)"
  sel=$(list_all_packages | $FINDER --delimiter='|' --with-nth=1,2 --preview "$0 --preview {1}" --preview-window=right:60% --multi --height=60% --prompt="Search> " --header="$header")
  [[ -z $sel ]] && return
  mapfile -t pkgs < <(printf '%s\n' "$sel" | sed 's/|.*//'); action_menu_for_pkgs "${pkgs[@]}"
}

menu_installed_packages() {
  local header sel; header="$(_status_header)"
  sel=$(list_installed | sed 's/|/\t/' | $FINDER --with-nth=1,2 --preview "$0 --preview {1}" --preview-window=right:60% --multi --height=60% --prompt="Installed> " --header="$header")
  [[ -z $sel ]] && return
  mapfile -t pkgs < <(printf '%s\n' "$sel" | cut -f1); action_menu_for_pkgs "${pkgs[@]}"
}

menu_upgradable() {
  local header sel; header="$(_status_header)"
  sel=$(list_upgradable | $FINDER --multi --height=40% --reverse --prompt="Upgradable> " --preview "$0 --preview {1}" --preview-window=right:60% --header="$header")
  [[ -z $sel ]] && return
  mapfile -t pkgs < <(printf '%s\n' "$sel"); run_mgr install "${pkgs[@]}"
}

menu_backup_restore() {
  local opts=("Backup installed packages" "Restore from file" "Cancel"); local choice
  choice=$(printf '%s\n' "${opts[@]}" | $FINDER --height=12% --reverse --prompt="Backup/Restore> " --header="$(_status_header)")
  [[ -z $choice ]] && return
  case "$choice" in
    "Backup installed packages") backup_installed ;;
    "Restore from file") read -r -p "Path: " f; [[ -n $f ]] && restore_from_file "$f" ;;
  esac
}

menu_system_maintenance() {
  local opts=("Update" "Upgrade" "Autoremove" "Clean" "Choose manager" "Cancel"); local choice
  choice=$(printf '%s\n' "${opts[@]}" | $FINDER --height=18% --reverse --prompt="Maintenance> " --header="$(_status_header)")
  [[ -z $choice ]] && return
  case "$choice" in
    Update) run_mgr update ;;
    Upgrade) run_mgr upgrade ;;
    Autoremove) run_mgr autoremove ;;
    Clean) run_mgr clean ;;
    "Choose manager") choose_manager ;;
  esac
}

main_menu() {
  evict_old_cache
  local menu=("Search packages" "Installed" "Upgradable" "Backup/Restore" "Maintenance" "Choose manager" "Quit")
  while true; do
    local choice; choice=$(printf '%s\n' "${menu[@]}" | $FINDER --height=20% --reverse --prompt="apt-parus> " --header="$(_status_header)")
    [[ -z $choice ]] && break
    case "$choice" in
      "Search packages") menu_search_packages ;;
      Installed) menu_installed_packages ;;
      Upgradable) menu_upgradable ;;
      "Backup/Restore") menu_backup_restore ;;
      Maintenance) menu_system_maintenance ;;
      "Choose manager") choose_manager ;;
      Quit) break ;;
    esac
  done
}

# install + completion
_install_self() {
  local dest="${HOME%/}/.local/bin/apt-parus"; mkdir -p "${HOME%/}/.local/bin"
  cp -f "$0" "$dest"; chmod +x "$dest"; printf 'Installed: %s\n' "$dest"
  local compdir="${HOME%/}/.local/share/bash-completion/completions"; mkdir -p "$compdir"
  cat >"$compdir/apt-parus" <<'BASHCOMP'
_complete_apt_parus() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  opts="search installed upgradable install remove purge backup restore maintenance choose-manager quit"
  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") ); return 0
  fi
  case "${COMP_WORDS[1]}" in
    install|remove|purge) COMPREPLY=( $(compgen -W "$(apt-cache pkgnames | tr '\n' ' ')" -- "$cur") ) ;;
    restore) COMPREPLY=( $(compgen -f -- "$cur") ) ;;
  esac
}
complete -F _complete_apt_parus apt-parus
BASHCOMP
  printf 'Completion installed: %s/apt-parus\n' "$compdir"
}

# CLI conveniences
if [[ $# -gt 0 ]]; then
  case "$1" in
    --install) _install_self; exit 0 ;;
    --preview) [[ -z "${2:-}" ]] && { echo "usage: $0 --preview <pkg>" >&2; exit 2; }; _cached_preview_print "$2"; exit 0 ;;
    install|remove|purge) [[ $# -lt 2 ]] && { echo "Usage: $0 $1 <pkgs...>"; exit 2; }; cmd="$1"; shift; run_mgr "$cmd" "$@"; exit 0 ;;
    help|-h|--help) printf 'Usage: apt-parus [--install] | [install|remove|purge <pkgs...>]\nRun without args to start TUI.\n'; exit 0 ;;
  esac
fi

cat <<'EOF'
apt-parus: sk-preferred frontend for apt/nala/apt-fast
Controls: fuzzy-search, multi-select (TAB), Enter to confirm
EOF

main_menu
