#!/usr/bin/env bash
# apt-parus — fzf/sk TUI for apt/nala/apt-fast with cached previews and simple installer
# - preview cache at ${XDG_CACHE_HOME:-$HOME/.cache}/apt-parus
# - TTL configurable via APT_PARUS_CACHE_TTL (seconds, default 86400)
# - install to ~/.local/bin with --install (also installs bash completion)
#  style: [[ ... ]], 2-space indentation, &>/dev/null || :

set -euo pipefail
shopt -s nullglob globstar

export LC_ALL=C LANG=C
: "${SHELL:=/bin/bash}"
: "${XDG_CACHE_HOME:=${HOME:-$HOME}/.cache}"
CACHE_DIR="${XDG_CACHE_HOME}/apt-parus"
mkdir -p "$CACHE_DIR"

: "${APT_PARUS_CACHE_TTL:=86400}"  # default 1 day

# Finder detection
FINDER=""
if command -v fzf &>/dev/null; then
  FINDER="fzf"
elif command -v sk &>/dev/null; then
  FINDER="sk"
else
  echo "Please install fzf or skim (sk)." >&2
  exit 1
fi

# managers detection
HAS_NALA=0; HAS_APT_FAST=0
command -v nala &>/dev/null && HAS_NALA=1 || :
command -v apt-fast &>/dev/null && HAS_APT_FAST=1 || :

PRIMARY_MANAGER="apt"
[[ $HAS_NALA -eq 1 ]] && PRIMARY_MANAGER="nala"
[[ $HAS_NALA -eq 0 && $HAS_APT_FAST -eq 1 ]] && PRIMARY_MANAGER="apt-fast"

# -------------------------
# Preview cache utilities
# -------------------------
_cache_file_for() {
  local pkg="$1"
  printf '%s/%s.cache' "$CACHE_DIR" "${pkg//[^a-zA-Z0-9._+-]/_}"
}

_cache_valid() {
  local f; f="$1"
  [[ -f $f ]] || return 1
  local age; age=$(( $(date +%s) - $(stat -c %Y -- "$f") ))
  (( age < APT_PARUS_CACHE_TTL ))
}

_generate_preview() {
  local pkg="$1"
  local out; out="$(_cache_file_for "$pkg")"
  local tmp; tmp="${out}.$$.tmp"
  {
    apt-cache show "$pkg" 2>/dev/null || :
    printf '\n--- changelog (first 200 lines) ---\n'
    command -v apt-get &>/dev/null && apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :
  } >"$tmp" 2>/dev/null || :    # don't fail preview generation
  # strip color codes
  sed -i 's/\x1b\[[0-9;]*m//g' "$tmp" 2>/dev/null || :
  mv -f "$tmp" "$out"
  printf '%s' "$out"
}

_cached_preview_print() {
  local pkg="$1"
  local cache; cache="$(_cache_file_for "$pkg")"
  if _cache_valid "$cache"; then
    cat "$cache"
  else
    _generate_preview "$pkg" >/dev/null
    cat "$cache" 2>/dev/null || echo "(no preview)"
  fi
}

# If called as --preview <pkg> print cached preview and exit (used by finder)
if [[ "${1:-}" == "--preview" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "usage: $0 --preview <pkg>" >&2
    exit 1
  fi
  _cached_preview_print "$2"
  exit 0
fi

# -------------------------
# Manager runner (prefers apt-get with apt)
# -------------------------
run_mgr() {
  # run_mgr <action> [pkg...]
  local action="$1"; shift || :
  local pkgs=("$@")
  local cmd=()
  case "$PRIMARY_MANAGER" in
    nala)
      case "$action" in
        update) cmd=(nala update) ;;
        upgrade) cmd=(nala upgrade -y) ;;
        autoremove) cmd=(nala autoremove -y) ;;
        clean) cmd=(nala clean) ;;
        *) cmd=(nala "$action" -y "${pkgs[@]}") ;;
      esac
      ;;
    apt-fast)
      case "$action" in
        update) cmd=(apt-fast update) ;;
        upgrade) cmd=(apt-fast upgrade -y) ;;
        autoremove) cmd=(apt-fast autoremove -y) ;;
        clean) cmd=(apt-fast clean) ;;
        *) cmd=(apt-fast "$action" -y "${pkgs[@]}") ;;
      esac
      ;;
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
      esac
      ;;
  esac
  printf 'Running: sudo %s\n' "${cmd[*]}"
  sudo "${cmd[@]}"
}

choose_manager() {
  local opts=("apt")
  [[ $HAS_NALA -eq 1 ]] && opts+=("nala")
  [[ $HAS_APT_FAST -eq 1 ]] && opts+=("apt-fast")
  local choice
  choice=$(printf '%s\n' "${opts[@]}" | $FINDER --height=12% --reverse --prompt="Manager> ")
  [[ -n $choice ]] && PRIMARY_MANAGER="$choice"
}

# -------------------------
# Package lists
# -------------------------
list_all_packages() {
  apt-cache search . 2>/dev/null | sed -E 's/ - /|/; s/\t/ /g'
}

list_installed() {
  dpkg-query -W -f='${binary:Package}|${Version}\n' 2>/dev/null || :
}

list_upgradable() {
  apt list --upgradable 2>/dev/null | awk -F'/' 'NR>1{print $1}'
}

backup_installed() {
  local outfile="${1:-pkglist-$(date +%F).txt}"
  dpkg-query -W -f='${binary:Package}\n' | sort -u > "$outfile"
  printf 'Saved installed package list: %s\n' "$outfile"
}

restore_from_file() {
  local file="$1"
  [[ ! -f $file ]] && { echo "File not found: $file" >&2; return 1; }
  mapfile -t pkgs < <(sed '/^$/d' "$file")
  [[ ${#pkgs[@]} -eq 0 ]] && { echo "No packages in file."; return 0; }
  mapfile -t sel < <(printf '%s\n' "${pkgs[@]}" | $FINDER --multi --height=40% --reverse --prompt="Confirm install> ")
  [[ ${#sel[@]} -eq 0 ]] && return
  run_mgr install "${sel[@]}"
}

show_changelog() {
  local pkg="$1"
  command -v apt-get &>/dev/null && (apt-get changelog "$pkg" 2>/dev/null || echo "No changelog for $pkg") || echo "apt-get unavailable"
}

# -------------------------
# Action menu / UI
# -------------------------
action_menu_for_pkgs() {
  local pkgs=("$@")
  local actions=("Install" "Remove" "Purge" "Changelog" "Cancel")
  local act
  act=$(printf '%s\n' "${actions[@]}" | $FINDER --height=12% --reverse --prompt="Action for ${#pkgs[@]} pkgs> ")
  [[ -z $act ]] && return
  case "$act" in
    Install) run_mgr install "${pkgs[@]}" ;;
    Remove) run_mgr remove "${pkgs[@]}" ;;
    Purge) run_mgr purge "${pkgs[@]}" ;;
    Changelog) for p in "${pkgs[@]}"; do show_changelog "$p"; read -r -p "Enter to continue..." || :; done ;;
    Cancel) return ;;
  esac
}

menu_search_packages() {
  local selection
  selection=$(list_all_packages | $FINDER --delimiter='|' --with-nth=1,2 \
    --preview "$0 --preview {1}" --preview-window=right:60% --multi --height=60% --prompt="Search> ")
  [[ -z $selection ]] && return
  mapfile -t selpkgs < <(printf '%s\n' "$selection" | sed 's/|.*//')
  action_menu_for_pkgs "${selpkgs[@]}"
}

menu_installed_packages() {
  local selection
  selection=$(list_installed | sed 's/|/\t/' | $FINDER --with-nth=1,2 \
    --preview "$0 --preview {1}" --preview-window=right:60% --multi --height=60% --prompt="Installed> ")
  [[ -z $selection ]] && return
  mapfile -t selpkgs < <(printf '%s\n' "$selection" | cut -f1)
  action_menu_for_pkgs "${selpkgs[@]}"
}

menu_upgradable() {
  local selection
  selection=$(list_upgradable | $FINDER --multi --height=40% --reverse --prompt="Upgradable> " \
    --preview "$0 --preview {1}" --preview-window=right:60%)
  [[ -z $selection ]] && return
  mapfile -t selpkgs < <(printf '%s\n' "$selection")
  run_mgr install "${selpkgs[@]}"
}

menu_backup_restore() {
  local opts=("Backup installed packages" "Restore from file" "Cancel")
  local choice
  choice=$(printf '%s\n' "${opts[@]}" | $FINDER --height=12% --reverse --prompt="Backup/Restore> ")
  [[ -z $choice ]] && return
  case "$choice" in
    "Backup installed packages") backup_installed ;;
    "Restore from file") read -r -p "Path: " file; [[ -n $file ]] && restore_from_file "$file" ;;
  esac
}

menu_system_maintenance() {
  local opts=("Update" "Upgrade" "Autoremove" "Clean" "Choose manager" "Cancel")
  local choice
  choice=$(printf '%s\n' "${opts[@]}" | $FINDER --height=18% --reverse --prompt="Maintenance> ")
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
  local menu=("Search packages" "Installed" "Upgradable" "Backup/Restore" "Maintenance" "Choose manager" "Quit")
  while true; do
    local choice
    choice=$(printf '%s\n' "${menu[@]}" | $FINDER --height=20% --reverse --prompt="apt-parus> ")
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

# -------------------------
# Self-install / completion
# -------------------------
_install_self() {
  local dest="${HOME%/}/.local/bin/apt-parus"
  mkdir -p "${HOME%/}/.local/bin"
  cp -f "$0" "$dest"
  chmod +x "$dest"
  printf 'Installed to: %s\n' "$dest"

  # user-level bash-completion dir
  local compdir="${HOME%/}/.local/share/bash-completion/completions"
  mkdir -p "$compdir"
  cat >"$compdir/apt-parus" <<'BASHCOMP'
_complete_apt_parus() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[1]:-}"
  opts="search installed upgradable install remove purge backup restore maintenance choose-manager quit"
  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    return 0
  fi
  case "$prev" in
    install|remove|purge)
      COMPREPLY=( $(compgen -W "$(apt-cache pkgnames | tr '\n' ' ')" -- "$cur") )
      ;;
    restore) COMPREPLY=( $(compgen -f -- "$cur") ) ;;
  esac
}
complete -F _complete_apt_parus apt-parus
BASHCOMP
  printf 'Bash completion installed to: %s\n' "$compdir/apt-parus"
  printf 'To enable completion now: source %s/apt-parus\n' "$compdir"
}

# -------------------------
# CLI support (small)
# -------------------------
# simple non-interactive helpers: apt-parus install <pkg...> remove <pkg...> ...
if [[ $# -gt 0 ]]; then
  case "$1" in
    --install) _install_self; exit 0 ;;
    install|remove|purge)
      cmd="$1"; shift
      [[ $# -eq 0 ]] && { echo "Usage: $0 ${cmd} <pkg...>"; exit 2; }
      run_mgr "$cmd" "$@"; exit 0
      ;;
    --preview)
      # handled at top; fallthrough
      _cached_preview_print "$2"; exit 0
      ;;
    help|--help|-h)
      cat <<'USAGE'
Usage: apt-parus [--install] | [install|remove|purge <pkgs...>]
Run without args to start interactive TUI.
--install   Install this script to ~/.local/bin and add bash completion.
USAGE
      exit 0
      ;;
  esac
fi

cat <<'EOF'
apt-parus: fzf/sk frontend for apt/nala/apt-fast
Controls: fuzzy-search, TAB to multi-select (if supported), Enter to confirm
EOF

main_menu
