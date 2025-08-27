#!/usr/bin/env bash
# compact apt-parus-tui — fzf/sk TUI for apt/nala/apt-fast
# 2-space indentation, uses apt-get when apt is chosen.

export LC_ALL=C LANG=C SHELL=bash
set -euo pipefail
shopt -s nullglob globstar

# finder
FINDER=""
if command -v fzf &>/dev/null; then
  FINDER="fzf"
elif command -v sk &>/dev/null; then
  FINDER="sk"
else
  echo "Please install fzf or skim (sk)." >&2
  exit 1
fi

# managers
HAS_NALA=0; HAS_APT_FAST=0
command -v nala &>/dev/null && HAS_NALA=1 || :
command -v apt-fast &>/dev/null && HAS_APT_FAST=1 || :

# default manager preference: nala > apt-fast > apt
PRIMARY_MANAGER="apt"
[[ $HAS_NALA -eq 1 ]] && PRIMARY_MANAGER="nala"
[[ $HAS_NALA -eq 0 && $HAS_APT_FAST -eq 1 ]] && PRIMARY_MANAGER="apt-fast"

# centralized runner: supports common actions and prefers apt-get for apt
run_mgr() {
  # run_mgr <action> <pkg...>
  local action="$1"; shift
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
      # apt chosen — use apt-get for speed where applicable
      case "$action" in
        update) cmd=(apt-get update) ;;
        upgrade) cmd=(apt-get upgrade -y) ;;
        install) cmd=(apt-get install -y "${pkgs[@]}") ;;
        remove) cmd=(apt-get remove -y "${pkgs[@]}") ;;
        purge) cmd=(apt-get purge -y "${pkgs[@]}") ;;
        autoremove) cmd=(apt-get autoremove -y) ;;
        clean) cmd=(apt-get clean) ;; # clean takes no -y
        *) cmd=(apt "$action" "${pkgs[@]}") ;; # fallback
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

_preview_pkg() {
  local pkg="$1"
  apt-cache show "$pkg" 2>/dev/null || :
  printf '\n--- changelog (first 200 lines) ---\n'
  command -v apt-get &>/dev/null && apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :
}
export -f _preview_pkg

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
  # confirm selection via finder, then install in one batch
  mapfile -t sel < <(printf '%s\n' "${pkgs[@]}" | $FINDER --multi --height=40% --reverse --prompt="Confirm install> ")
  [[ ${#sel[@]} -eq 0 ]] && return
  run_mgr install "${sel[@]}"
}

show_changelog() {
  local pkg="$1"
  command -v apt-get &>/dev/null && (apt-get changelog "$pkg" 2>/dev/null || echo "No changelog for $pkg") || echo "apt-get unavailable"
}

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
  selection=$(list_all_packages | $FINDER --delimiter='|' --with-nth=1,2 --preview "bash -c '_preview_pkg \"\$(echo {} | cut -d\"|\" -f1)\"'" --preview-window=right:60% --multi --height=60% --prompt="Search> ")
  [[ -z $selection ]] && return
  mapfile -t selpkgs < <(printf '%s\n' "$selection" | sed 's/|.*//')
  action_menu_for_pkgs "${selpkgs[@]}"
}

menu_installed_packages() {
  local selection
  selection=$(list_installed | sed 's/|/\t/' | $FINDER --with-nth=1,2 --preview 'apt-cache show $(echo {} | cut -f1)' --preview-window=right:60% --multi --height=60% --prompt="Installed> ")
  [[ -z $selection ]] && return
  mapfile -t selpkgs < <(printf '%s\n' "$selection" | cut -f1)
  action_menu_for_pkgs "${selpkgs[@]}"
}

menu_upgradable() {
  local selection
  selection=$(list_upgradable | $FINDER --multi --height=40% --reverse --prompt="Upgradable> " --preview 'apt-cache show {}' --preview-window=right:60%)
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

cat <<'EOF'
apt-parus-tui: fzf/sk front-end for apt/nala/apt-fast
Controls: fuzzy-search, TAB to multi-select (if supported), Enter to confirm
EOF

main_menu
