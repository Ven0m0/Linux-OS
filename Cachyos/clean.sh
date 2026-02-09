#!/usr/bin/env bash
# clean.sh - Optimized System & Privacy Cleaner
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C

# --- Config & Helpers ---
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' M=$'\e[35m' C=$'\e[36m' X=$'\e[0m'
has() { command -v "$1" &>/dev/null; }
try() { "$@" >/dev/null 2>&1 || true; }
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
  [[ -d $dir ]] && sudo du -sm "$dir" 2>/dev/null | awk '{print $1}' || echo 0
}

clean_pkgs() {
  log "Cleaning package caches..."
  if has pacman; then
    # Measure before cleanup
    local pacman_before paru_before yay_before
    pacman_before=$(get_cache_size "/var/cache/pacman/pkg")
    paru_before=$(get_cache_size "$HOME/.cache/paru/clone")
    yay_before=$(get_cache_size "$HOME/.cache/yay")

    # Remove stuck download directories
    sudo find "/var/cache/pacman/pkg" -maxdepth 1 -type d -name "download-*" -exec rm -rf {} +

    # Aggressive cache purge
    if has paru; then yes | paru -Scc --noconfirm &>/dev/null || :; fi
    yes | sudo pacman -Scc --noconfirm &>/dev/null || :
    has paccache && try sudo paccache -rk1 &>/dev/null || :

    # Remove orphans
    local orphans
    orphans=$(pacman -Qtdq) || true
    if [[ -n $orphans ]]; then
      try sudo pacman -Rns $orphans --noconfirm || :
    fi

    # Measure after cleanup
    local pacman_after paru_after yay_after total_freed
    pacman_after=$(get_cache_size "/var/cache/pacman/pkg")
    paru_after=$(get_cache_size "$HOME/.cache/paru/clone")
    yay_after=$(get_cache_size "$HOME/.cache/yay")
    total_freed=$(((pacman_before - pacman_after) + (paru_before - paru_after) + (yay_before - yay_after)))

    [[ $total_freed -gt 0 ]] && log "Package cache freed: ${total_freed}MB"
  elif has apt-get; then
    try sudo apt-get autoremove -y && try sudo apt-get clean
  elif has dnf; then
    try sudo dnf autoremove -y && try sudo dnf clean all
  elif has zypper; then
    try sudo zypper clean --all
  fi

  if has flatpak; then
    log "Cleaning Flatpak..."
    try flatpak uninstall --unused -y
    try rm -rf "$HOME/.var/app/*/cache/*"
  fi
}

clean_dev() {
  log "Cleaning dev tools..."
  has cargo-cache && {
    try cargo cache -efg
    try cargo cache -ef trim --limit 1B
  }
  has uv && try uv cache clean
  has bun && try bun -g pm cache rm
  has pnpm && {
    try pnpm prune
    try pnpm store prune
  }
  has go && try go clean -modcache
  has pip && try pip cache purge
  has npm && try npm cache clean --force
  has yarn && try yarn cache clean
  rm -rf ~/.cache/{pip,pipenv,poetry,node-gyp,npm,yarn} 2>/dev/null || true
}

clean_sys() {
  log "Cleaning system paths..."
  try sudo rm -rf /tmp/* /var/tmp/* /var/log/journal/*
  try sudo journalctl --vacuum-time=1sec --rotate
  try rm -rf ~/.cache/thumbnails ~/.cache/mozilla/firefox/*.default*/cache2
  try rm -rf ~/.local/share/Trash/*
  # TODO: add steam cleaning:
  # ~/.steam/root/steamapps/shadercache ~/.steam/root/steamapps/temp ~/.steam/root/appcache/httpcache ~/.steam/root/appcache/librarycache ~/.steam/root/logs
  # also integrate these
  # dbus-update-activation-environment --systemd --all
  # dbus-cleanup-sockets

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

privacy_config() {
  log "Applying privacy configurations..."
  # TODO: add fish and put it in the general system cleanup
  try rm -f ~/.bash_history ~/.zsh_history ~/.lesshst ~/.wget-hsts
  log "Privacy steps applied."
}

# --- Main ---
main() {
  # Refresh sudo credential cache
  sudo -v
  [[ ${1:-} == "config" ]] && {
    banner
    privacy_config
    exit 0
  }

  banner
  local start_du
  start_du=$(df -k / | awk 'NR==2 {print $3}')

  # Sync and drop caches
  sync
  echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

  # Optimize databases
  log "Optimizing SQLite databases..."
  find ~/ -type f -regextype posix-egrep -regex '.*\.(db|sqlite)' \
    -exec bash -c '[ "$(file -b --mime-type "$1")" = "application/vnd.sqlite3" ] && sqlite3 "$1" "VACUUM; REINDEX;"' _ {} \; 2>/dev/null

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
