#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
# Core helper functions
has(){ command -v -- "$1" &>/dev/null; }
# DietPi functions
load_dietpi_globals(){ [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :; }
run_dietpi_cleanup(){
  if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then
    if ! sudo dietpi-update 1 && ! sudo /boot/dietpi/dietpi-update 1; then
      printf '%s\n' "dietpi-update failed (both standard and fallback commands)." >&2
    fi
    sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null || :
    sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null || :
  fi
}
# APT functions
clean_apt_cache(){
  sudo apt-get clean -y 2>/dev/null || :
  sudo apt-get autoclean -y 2>/dev/null || :
  sudo apt-get autoremove --purge -y 2>/dev/null || :
}
# System cleanup functions
clean_cache_dirs(){
  sudo rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/* 2>/dev/null || :
  rm -rf ~/.cache/* ~/.thumbnails/* ~/.cache/thumbnails/* 2>/dev/null || :
  sudo rm -rf /root/.cache/* 2>/dev/null || :
}
clean_trash(){
  rm -rf ~/.local/share/Trash/* 2>/dev/null || :
  sudo rm -rf /root/.local/share/Trash/* 2>/dev/null || :
  rm -rf ~/snap/*/*/.local/share/Trash/* 2>/dev/null || :
  rm -rf ~/.var/app/*/data/Trash/* 2>/dev/null || :
}
clean_crash_dumps(){
  has coredumpctl && sudo coredumpctl --quiet --no-legend clean 2>/dev/null || :
  sudo rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || :
}
clean_history_files(){
  rm -f ~/.python_history ~/.bash_history 2>/dev/null || :
  sudo rm -f /root/.python_history /root/.bash_history 2>/dev/null || :
  history -c 2>/dev/null || :
}
clean_journal_logs(){
  sudo journalctl --rotate --vacuum-size=1 --flush --sync -q 2>/dev/null || :
  sudo rm -rf --preserve-root -- /run/log/journal/* /var/log/journal/* 2>/dev/null || :
  sudo systemd-tmpfiles --clean 2>/dev/null || :
}
# Banner
printf '%s\n' '
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗     ███████╗ ██████╗██████╗ ██╗██████╗ ████████╗
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝     ██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗    ███████╗██║     ██████╔╝██║██████╔╝   ██║
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║    ╚════██║██║     ██╔══██╗██║██╔═══╝    ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝    ███████║╚██████╗██║  ██║██║██║        ██║
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝     ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝
'
printf '%s\n' "Cleaning apt cache"
sudo rm -rf /var/lib/apt/lists/*
clean_apt_cache
sudo apt-get purge '?config-files' 2>/dev/null || :
printf '%s\n' "Cleaning leftover config files"
has dpkg && dpkg -l | awk '/^rc/ {print $2}' | xargs -r sudo apt-get purge -y 2>/dev/null || :
printf '%s\n' "orphan removal"
has deborphan && sudo deborphan | xargs -r sudo apt-get -y remove --purge --auto-remove 2>/dev/null || :
# UV cache cleaning
if has uv; then
  uv cache prune -q 2>/dev/null || :
  uv cache clean -q 2>/dev/null || :
fi
printf '%s\n' "Removing common cache directories and trash"
clean_cache_dirs
clean_trash
printf '%s\n' "Cleaning crash dumps and systemd coredumps"
clean_crash_dumps
printf '%s\n' "Clearing old history files..."
clean_history_files
printf '%s\n' "Vacuuming journal logs"
clean_journal_logs
printf '%s\n' "Running fstrim"
sudo fstrim -a --quiet-unsupported
printf '%s\n' "Removing old log files"
sudo find /var/log/ -name "*.log" -type f -mtime +3 -delete
sudo find /var/crash/ -name "core.*" -type f -mtime +3 -delete
sudo find /var/cache/apt/ -name "*.bin" -type f -mtime +3 -delete
sync
printf '3' | sudo tee /proc/sys/vm/drop_caches &>/dev/null
printf '%s\n' "System clean-up complete."
printf '%s\n' "Clearing DietPi..."
run_dietpi_cleanup
