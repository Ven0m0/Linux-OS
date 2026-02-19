#!/usr/bin/env bash
# clean.sh - Optimized System & Privacy Cleaner
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
# --- Config & Helpers ---
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' M=$'\e[35m' C=$'\e[36m' X=$'\e[0m'
has() { command -v "$1" &>/dev/null; }
try() { "$@" >/dev/null 2>&1 || :; }
log() { printf "%b[+]%b %s\n" "$G" "$X" "$*"; }
warn() { printf "%b[!]%b %s\n" "$Y" "$X" "$*" >&2; }
disk_usage() { df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}'; }
banner() {
  printf "%bSystem Cleaner%b\n" "$C" "$X"
  printf "User: %s | Host: %s | Disk: %s\n" "${USER}" "${HOSTNAME}" "$(disk_usage)"
}
# --- Core Logic ---
get_cache_size() {
  local dir=$1
  if [[ -d $dir ]]; then
    sudo du -sm "$dir" 2>/dev/null | awk '{print $1}' || echo 0
  else
    echo 0
  fi
}
clean_pkgs() {
  log "Cleaning package caches..."
  if has pacman; then
    # Measure before cleanup
    local pacman_before paru_before yay_before
    local pacman_after paru_after yay_after total_freed

    pacman_before=$(get_cache_size "/var/cache/pacman/pkg")
    paru_before=$(get_cache_size "${HOME}/.cache/paru/clone")
    yay_before=$(get_cache_size "${HOME}/.cache/yay")

    # Remove stuck download directories
    sudo find "/var/cache/pacman/pkg" -maxdepth 1 -type d -name "download-*" -exec rm -rf {} +

    # Aggressive cache purge
    if has paru; then
      paru -Scc --noconfirm &>/dev/null || :
      paru -c --noconfirm &>/dev/null || :
    else
      sudo pacman -Scc --noconfirm &>/dev/null || :
    fi

    # Remove orphans
    local orphans
    orphans=$(pacman -Qtdq) || :
    if [[ -n $orphans ]]; then
      try sudo pacman -Rns --noconfirm "$orphans" || :
    fi

    # Measure after cleanup
    pacman_after=$(get_cache_size "/var/cache/pacman/pkg")
    paru_after=$(get_cache_size "${HOME}/.cache/paru/clone")
    yay_after=$(get_cache_size "${HOME}/.cache/yay")

    total_freed=$(((pacman_before - pacman_after) + (paru_before - paru_after) + (yay_before - yay_after)))
    [[ $total_freed -gt 0 ]] && log "Package cache freed: ${total_freed}MB"
  elif has apt-get; then
    sudo apt-get autoremove -y --purge
    sudo apt-get clean -y; sudo apt-get autoclean -y
  fi
  if has flatpak; then
    log "Cleaning Flatpak..."
    try flatpak uninstall --unused -y; sudo flatpak uninstall --unused -y
    try rm -rf "${HOME}/.var/app/*/cache/*"
  fi
}
clean_dev() {
  log "Cleaning dev tools..."
  has cargo-cache && {
    try cargo cache -efg; try cargo cache -ef trim --limit 1B
  }
  has uv && try uv cache clean --force
  has bun && try bun -g pm cache rm
  has pnpm && try pnpm store prune
  has go && try go clean -modcache
  has pip && try pip cache purge
  has npm && try npm cache clean --force
  has yarn && try yarn cache clean
  rm -rf ~/.cache/{pip,pipenv,poetry,node-gyp,npm,yarn} 2>/dev/null || :
}
clean_sys() {
  log "Cleaning system paths..."
  try sudo rm -rf /tmp/* /var/tmp/* /var/log/journal/*
  try sudo journalctl --vacuum-time=1sec --rotate
  try rm -rf ~/.cache/thumbnails ~/.cache/mozilla/firefox/*.default*/cache2
  try rm -rf ~/.local/share/Trash/*
  # Steam cleaning
  try rm -rf ~/.steam/root/{steamapps/{shadercache,temp},appcache/{httpcache,librarycache},logs}
  # DBus integration
  try dbus-update-activation-environment --systemd --all
  try dbus-cleanup-sockets
  if has bleachbit; then
    log "Running BleachBit..."
    try bleachbit -c --preset
    try sudo bleachbit -c --preset
  fi
  has localepurge && try sudo localepurge
  try sudo fstrim -av
  # Check only if xfs filesystem
  if [[ $(findmnt -n -o FSTYPE /) == "xfs" ]]; then
    try sudo xfs_scrub /
  fi
}
# --- Main ---
main() {
  # Refresh sudo credential cache
  sudo -v
  [[ ${1:-} == "config" ]] && {
    banner
    exit 0
  }
  banner
  local start_du
  start_du=$(df -k / | awk 'NR==2 {print $3}')
  # Sync and drop caches
  sync
  echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
  # Optimize databases
  log "Optimizing SQLite databases..."
  if command -v sqlite3 &>/dev/null; then
    local jobs
    jobs=$(nproc 2>/dev/null || echo 4)
    find "$HOME" \
      -type d \( -name .git -o -name node_modules -o -name .npm -o -name .cargo -o -name .go -o -name .vscode -o -name Library -o -name __pycache__ \) -prune \
      -o -type f \( -name "*.db" -o -name "*.sqlite" \) -print0 |
      xargs -0 -P "$jobs" -I {} bash -c '
        if [[ "$(head -c 15 "$1")" == "SQLite format 3" ]]; then
          sqlite3 "$1" "VACUUM; REINDEX;"
        fi
      ' _ {} 2>/dev/null
  fi
  clean_pkgs
  clean_dev
  clean_sys
  local end_du
  end_du=$(df -k / | awk 'NR==2 {print $3}')
  local freed=$(((start_du - end_du) / 1024))
  printf "\n%bDone!%b Freed approx: %b%s MB%b\n" "$G" "$X" "$C" "$freed" "$X"
  printf "Current Disk: %s\n" "$(disk_usage)"
}
main "$@"
