#!/usr/bin/env bash
# clean.sh - Optimized System & Privacy Cleaner
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

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
clean_pkgs() {
  log "Cleaning package caches..."
  if has pacman; then
    sudo find "/var/cache/pacman/pkg" -maxdepth 1 -type d -name "download-*" -exec rm -rf {} +
    # TODO: implement https://github.com/dusklinux/dusky/blob/main/user_scripts/arch_setup_scripts/scripts/065_cache_purge.sh
    yes | paru -Scc --noconfirm &>/dev/null || :
    yes | sudo pacman -Scc --noconfirm &>/dev/null || :
    has paccache && try sudo paccache -rk1 &>/dev/null || :
    try sudo pacman -Rns $(pacman -Qtdq) --noconfirm || :
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
  has uv && try uv clean -q
  has bun && try bun pm cache rm
  has pnpm && {
    try pnpm prune
    try pnpm store prune
  }
  has go && try go clean -modcache
  has pip && try pip cache purge
  has npm && try npm cache clean --force
  has yarn && try yarn cache clean
  rm -rf ~/.cache/{pip,pipenv,poetry,node-gyp,npm,yarn}
}

clean_sys() {
  log "Cleaning system paths..."
  try sudo rm -rf /tmp/* /var/tmp/* /var/log/journal/*
  try sudo journalctl --vacuum-time=2weeks
  try rm -rf ~/.cache/thumbnails ~/.cache/mozilla/firefox/*.default*/cache2
  try rm -rf ~/.local/share/Trash/*
  if has bleachbit; then
    log "Running BleachBit..."
    try bleachbit -c --preset
    try sudo bleachbit -c --preset
  fi
  has localepurge && try sudo localepurge
  try sudo fstrim -a
  try sudo xfs_scrub /
}

privacy_config() {
  log "Applying privacy configurations..."
  # Example privacy toggles - expand based on needs
  try rm -f ~/.bash_history ~/.zsh_history ~/.lesshst ~/.wget-hsts
  try ln -sf /dev/null ~/.bash_history
  log "Privacy steps applied."
}

# --- Main ---
main() {
  [[ ${1:-} == "config" ]] && {
    banner
    privacy_config
    exit 0
  }

  banner
  local start_du
  start_du=$(df -k / | awk 'NR==2 {print $3}')

  # Sync and drop caches for accurate memory measurement/cleaning
  sync
  echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
  # Optimize databases, IMPORTANT
  find ~/ -type f -regextype posix-egrep -regex '.*\.(db|sqlite)' \
    -exec bash -c '[ "$(file -b --mime-type {})" = "application/vnd.sqlite3" ] && sqlite3 {} "VACUUM; REINDEX;"' \; 2>/dev/null

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
