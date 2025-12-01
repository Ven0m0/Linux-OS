#!/usr/bin/env bash
# Optimized: 2025-11-21 - Applied bash optimization techniques
#──────────── Setup ────────────────────
# Setup environment
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'
export LC_ALL=C LANG=C DEBIAN_FRONTEND=noninteractive

# Initialize working directory
WORKDIR="$(cd "${"${BASH_SOURCE[0]}"%/*}" && pwd)"
cd "$WORKDIR" || {
  echo "Failed to change to working directory: $WORKDIR" >&2
  exit 1
}
# Check if a command exists
has(){ command -v -- "$1" &>/dev/null; }
# Get the name of a command from PATH
hasname(){
  local x
  if ! x=$(type -P -- "$1"); then
    return 1
  fi
  printf '%s\n' "${x##*/}"
}

# Load DietPi globals if available
load_dietpi_globals(){ [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :; }

# Run DietPi cleanup commands if available
run_dietpi_cleanup(){
  if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then
    if ! sudo dietpi-update 1 && ! sudo /boot/dietpi/dietpi-update 1; then
      echo "Warning: dietpi-update failed (both standard and fallback commands)." >&2
    fi
    sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null || :
    sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null || :
  fi
}

# Clean APT package manager cache
clean_apt_cache(){
  sudo apt-get clean -y
  sudo apt-get autoclean -y
  sudo apt-get autoremove --purge -y
}
# Clean system cache directories
clean_cache_dirs(){
  sudo rm -rf /tmp/* 2>/dev/null || :
  sudo rm -rf /var/tmp/* 2>/dev/null || :
  sudo rm -rf /var/cache/apt/archives/* 2>/dev/null || :
  rm -rf ~/.cache/* 2>/dev/null || :
  sudo rm -rf /root/.cache/* 2>/dev/null || :
  rm -rf ~/.thumbnails/* 2>/dev/null || :
  rm -rf ~/.cache/thumbnails/* 2>/dev/null || :
}
# Empty trash directories
clean_trash(){
  rm -rf ~/.local/share/Trash/* 2>/dev/null || :
  sudo rm -rf /root/.local/share/Trash/* 2>/dev/null || :
  rm -rf ~/snap/*/*/.local/share/Trash/* 2>/dev/null || :
  rm -rf ~/.var/app/*/data/Trash/* 2>/dev/null || :
}
# Clean crash dumps and core dumps
clean_crash_dumps(){
  if command -v coredumpctl &>/dev/null; then
    sudo coredumpctl --quiet --no-legend clean 2>/dev/null || :
  fi
  sudo rm -rf /var/crash/* 2>/dev/null || :
  sudo rm -rf /var/lib/systemd/coredump/* 2>/dev/null || :
}
# Clean shell and Python history files
clean_history_files(){
  rm -f ~/.python_history 2>/dev/null || :
  sudo rm -f /root/.python_history 2>/dev/null || :
  rm -f ~/.bash_history 2>/dev/null || :
  sudo rm -f /root/.bash_history 2>/dev/null || :
  history -c 2>/dev/null || :
}
# Clean systemd journal logs
clean_journal_logs(){
  sudo journalctl --rotate --vacuum-size=1 --flush --sync -q 2>/dev/null || :
  sudo rm -rf --preserve-root -- /run/log/journal/* /var/log/journal/* 2>/dev/null || :
  sudo systemd-tmpfiles --clean 2>/dev/null || :
}
#──────────── Sudo ────────────────────
load_dietpi_globals
sync
#─────────────────────────────────────────────────────────────
echo
echo " ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗     ███████╗ ██████╗██████╗ ██╗██████╗ ████████╗"
echo "██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝     ██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝"
echo "██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗    ███████╗██║     ██████╔╝██║██████╔╝   ██║   "
echo "██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║    ╚════██║██║     ██╔══██╗██║██╔═══╝    ██║   "
echo "╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝    ███████║╚██████╗██║  ██║██║██║        ██║   "
echo " ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝     ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   "
echo

echo "Cleaning apt cache"
sudo rm -rf /var/lib/apt/lists/*
clean_apt_cache
sudo apt-get purge ?config-files 2>/dev/null || :
echo "Cleaning leftover config files"
if has dpkg; then
  dpkg -l | awk '/^rc/ { print $2 }' | xargs -r sudo apt-get purge -y 2>/dev/null || :
fi
echo "orphan removal"
if has deborphan; then
  sudo deborphan | xargs -r sudo apt-get -y remove --purge --auto-remove 2>/dev/null || :
fi
# UV cache cleaning
if has uv; then
  uv cache prune -q 2>/dev/null || :
  uv cache clean -q 2>/dev/null || :
fi
echo "Removing common cache directories and trash"
clean_cache_dirs
clean_trash
echo "Cleaning crash dumps and systemd coredumps"
clean_crash_dumps
echo "Clearing old history files..."
clean_history_files
echo "Vacuuming journal logs"
clean_journal_logs
echo "Running fstrim"
sudo fstrim -a --quiet-unsupported
echo "Removind old log files"
sudo find /var/log/ -name "*.log" -type f -mtime +3 -delete
sudo find /var/crash/ -name "core.*" -type f -mtime +3 -delete
sudo find /var/cache/apt/ -name "*.bin" -type f -mtime +3 -delete

sync
echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
echo "System clean-up complete."
echo "Clearing DietPi..."
run_dietpi_cleanup
