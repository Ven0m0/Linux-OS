#!/usr/bin/env bash

# apt-parus-tui.sh
# A full TUI in the spirit of paruse/parus but for Debian/Ubuntu (apt, nala, apt-fast)
# Features:
#  - fuzzy search (fzf) or skim (sk) frontend
#  - preview package info, changelogs
#  - multi-select batch install/remove/purge
#  - backup/restore package lists
#  - update/upgrade using apt, nala, or apt-fast when available
#  - cache clean / autoremove
#
# Install dependencies: fzf or skim (sk), apt (on Debian/Ubuntu), optional: nala, apt-fast
#
#  Usage: source this file from your shell or make it executable and run:
#    ./apt-parus-tui.sh
#
#  Notes on style: uses [[ ... ]] tests, 2-space indentation, and uses '&>/dev/null || :' where appropriate.

export LC_ALL=C LANG=C SHELL=bash
shopt -s nullglob globstar

FINDER=""
if command -v fzf &>/dev/null || :; then
  FINDER="fzf"
elif command -v sk &>/dev/null || :; then
  FINDER="sk"
else
  echo "Please install fzf or skim (sk) to use this TUI." >&2
  exit 1
fi
# Detect available package frontends
HAS_NALA=0 HAS_APT_FAST=0
if command -v nala &>/dev/null || :; then
  HAS_NALA=1
fi
if command -v apt-fast &>/dev/null || :; then
  HAS_APT_FAST=1
fi
# Default primary manager (interactive will let you switch)
PRIMARY_MANAGER="apt"
if [[ $HAS_NALA -eq 1 ]]; then
  PRIMARY_MANAGER="nala"
elif [[ $HAS_APT_FAST -eq 1 ]]; then
  PRIMARY_MANAGER="apt-fast"
fi

# Helpers
run_mgr() {
  # run_mgr <action> <packages...>
  local action="$1"; shift
  local pkgs=("$@")
  local cmd
  case "$PRIMARY_MANAGER" in
    nala)
      cmd=(nala "$action" "-y" "${pkgs[@]}")
      ;;
    apt-fast)
      cmd=(apt-fast "$action" "-y" "${pkgs[@]}")
      ;;
    *)
      cmd=(apt "$action" "-y" "${pkgs[@]}")
      ;;
  esac
  echo "Running: sudo ${cmd[*]}"
  sudo "${cmd[@]}"
}

choose_manager() {
  # let user pick manager for upcoming operations
  local opts=("apt" )
  [[ $HAS_NALA -eq 1 ]] && opts+=("nala")
  [[ $HAS_APT_FAST -eq 1 ]] && opts+=("apt-fast")
  local choice
  choice=$(printf "%s\n" "${opts[@]}" | $FINDER --height=20% --reverse --prompt="Select manager> ")
  [[ -z $choice ]] && return
  PRIMARY_MANAGER="$choice"
}

_preview_pkg() {
  # preview: show apt-cache show and top-of-docs if available
  local pkg="$1"
  {
    apt-cache show "$pkg" 2>/dev/null || :
    echo
    echo "--- changelog (apt-get changelog) ---"
    if command -v apt-get &>/dev/null || :; then
      apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :
    fi
  } | sed 's/\x1b\[[0-9;]*m//g'
}

list_all_packages() {
  # use apt-cache search to produce lines like pkg|desc
  apt-cache search . 2>/dev/null | sed -E 's/ \- /|/; s/\t/ /g'
}

list_installed() {
  dpkg-query -W -f='${binary:Package}|${Version}\n' 2>/dev/null || :
}

list_upgradable() {
  # apt list --upgradable prints lines like pkg/version [upgradable from: x]
  apt list --upgradable 2>/dev/null | awk -F'/' 'NR>1{print $1}'
}

backup_installed() {
  local outfile="${1:-pkglist-$(date +%F).txt}"
  dpkg-query -W -f='${binary:Package}\n' | sort -u > "$outfile"
  echo "Saved installed package list to: $outfile"
}

restore_from_file() {
  local file="$1"
  [[ ! -f $file ]] && { echo "File not found: $file" >&2; return 1; }
  mapfile -t pkgs < <(sed '/^$/d' "$file")
  echo "About to  ${#pkgs[@]} packages from $file"
  printf '%s\n' "${pkgs[@]}" | $FINDER --multi --height=40% --reverse --prompt="Confirm  (select then Enter)> " | while read -r pkg; do
    [[ -z $pkg ]] && continue
    run_mgr install "$pkg"
  done
}

show_changelog() {
  local pkg="$1"
  if command -v apt-get &>/dev/null || :; then
    apt-get changelog "$pkg" 2>/dev/null || echo "No changelog available or apt-get lacks changelog for $pkg"
  else
    echo "apt-get not available to fetch changelog for $pkg"
  fi
}

menu_search_packages() {
  local selection
  selection=$(list_all_packages | $FINDER --delimiter='|' --with-nth=1,2 --preview 'bash -c "_preview_pkg \"$(echo {} | cut -d\"|\" -f1)\""' --preview-window=right:60% --multi --height=60% --prompt="Search packages> ")
  [[ -z $selection ]] && return
  # parse selected lines to package names
  mapfile -t selpkgs < <(printf '%s\n' "$selection" | sed 's/|.*//')
  echo "Selected ${#selpkgs[@]} package(s): ${selpkgs[*]}"
  action_menu_for_pkgs "${selpkgs[@]}"
}

menu_installed_packages() {
  local selection
  selection=$(list_installed | sed 's/|/\t/' | $FINDER --with-nth=1,2 --preview 'apt-cache show $(echo {} | cut -f1)' --preview-window=right:60% --multi --height=60% --prompt="Installed> " )
  [[ -z $selection ]] && return
  mapfile -t selpkgs < <(printf '%s\n' "$selection" | cut -f1)
  action_menu_for_pkgs "${selpkgs[@]}"
}

menu_upgradable() {
  local selection
  selection=$(list_upgradable | $FINDER --multi --height=40% --reverse --prompt="Upgradable> " --preview 'apt-cache show {}' --preview-window=right:60%)
  [[ -z $selection ]] && return
  mapfile -t selpkgs < <(printf '%s\n' "$selection")
  echo "Selected to upgrade: ${selpkgs[*]}"
  for p in "${selpkgs[@]}"; do
    run_mgr install "$p"
  done
}

action_menu_for_pkgs() {
  # $@ package names
  local pkgs=($@)
  local actions=("Install" "Remove" "Purge" "Show changelog" "Cancel")
  local act
  act=$(printf "%s\n" "${actions[@]}" | $FINDER --height=20% --reverse --prompt="Action for ${#pkgs[@]} pkgs> ")
  [[ -z $act ]] && return
  case "$act" in
    Install)
      for p in "${pkgs[@]}"; do run_mgr install "$p"; done
      ;;
    Remove)
      for p in "${pkgs[@]}"; do sudo $PRIMARY_MANAGER remove -y "$p"; done
      ;;
    Purge)
      for p in "${pkgs[@]}"; do sudo $PRIMARY_MANAGER purge -y "$p"; done
      ;;
    "Show changelog")
      for p in "${pkgs[@]}"; do show_changelog "$p"; read -r -p "Press Enter to continue..." || :; done
      ;;
    Cancel)
      return
      ;;
  esac
}

menu_backup_restore() {
  local opts=("Backup installed packages" "Restore from file" "Cancel")
  local choice
  choice=$(printf "%s\n" "${opts[@]}" | $FINDER --height=10% --reverse --prompt="Backup/Restore> ")
  [[ -z $choice ]] && return
  case "$choice" in
    "Backup installed packages")
      backup_installed
      ;;
    "Restore from file")
      read -r -p "Path to file: " file
      [[ -z $file ]] && return
      restore_from_file "$file"
      ;;
  esac
}

menu_system_maintenance() {
  local opts=("Update package lists" "Upgrade system" "Autoremove" "Clean cache" "Choose manager" "Cancel")
  local choice
  choice=$(printf "%s\n" "${opts[@]}" | $FINDER --height=20% --reverse --prompt="Maintenance> ")
  [[ -z $choice ]] && return
  case "$choice" in
    "Update package lists")
      case "$PRIMARY_MANAGER" in
        nala) sudo nala update ;;
        apt-fast) sudo apt-fast update ;;
        *) sudo apt-get update ;;
      esac
      ;;
    "Upgrade system")
      case "$PRIMARY_MANAGER" in
        nala) sudo nala upgrade -y ;;
        apt-fast) sudo apt-fast upgrade -y ;;
        *) sudo apt-get upgrade -y ;;
      esac
      ;;
    Autoremove)
      case "$PRIMARY_MANAGER" in
        nala) sudo nala autoremove -y ;;
        apt-fast) sudo apt-fast autoremove -y ;;
        *) sudo apt-get autoremove -y ;;
      esac
      ;;
    "Clean cache")
      case "$PRIMARY_MANAGER" in
        nala) sudo nala clean ;;
        apt-fast) sudo apt-fast clean -y ;;
        *) sudo apt-get clean -y ;;
      esac
      ;;
    "Choose manager")
      choose_manager
      ;;
  esac
}
main_menu() {
  local menu=("Search packages" "Installed" "Upgradable" "Backup/Restore" "Maintenance" "Choose manager" "Quit")
  while true; do
    local choice
    choice=$(printf "%s\n" "${menu[@]}" | $FINDER --height=20% --reverse --prompt="apt-parus> ")
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

# bootstrap
cat <<'EOF'
apt-parus-tui: small fzf/sk-based front-end for apt/nala/apt-fast
Controls: fuzzy-search, TAB to multi-select (if supported by your finder), Enter to confirm
EOF

main_menu
