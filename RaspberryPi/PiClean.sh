#!/usr/bin/env bash
#──────────── Setup ────────────────────
shopt -s nullglob globstar execfail
export LC_ALL=C LANG=C DEBIAN_FRONTEND=noninteractive
dirname(){ local tmp=${1:-.}; [[ $tmp != *[!/]* ]] && { printf '/\n'; return; }; tmp=${tmp%%"${tmp##*[!/]}" }; [[ $tmp != */* ]] && { printf '.\n'; return; }; tmp=${tmp%/*}; tmp=${tmp%%"${tmp##*[!/]}"}; printf '%s\n' "${tmp:-/}"; }
WORKDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
cd $WORKDIR || exit 1
#──────────── Helpers ────────────────────
has(){ command -v -- "$1" &>/dev/null; }
hasname(){
  local x
  if ! x=$(type -P -- "$1"); then
    return 1
  fi
  printf '%s\n' "${x##*/}"
}
xprintf(){ printf "%s\n" "$@"; }
#──────────── Sudo ────────────────────
[[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v 2>/dev/null || :
export HOME="/home/${SUDO_USER:-$USER}"; sync
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
sudo apt-get clean -yq
sudo apt-get autoclean -yq
sudo apt-get autoremove --purge -yq
sudo apt-get purge ?config-files
echo "Cleaning leftover config files"
dpkg -l | awk '/^rc/ { print $2 }' | xargs sudo apt-get purge -y

echo "orphan removal"
if command -v deborphan &>/dev/null; then
  sudo deborphan | xargs sudo apt-get -y remove --purge --auto-remove
fi

uv cache prune -q; uv cache clean -q
echo "Removing common cache directories and trash"
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo rm -rf /var/cache/*
rm -rf ~/.cache/*
sudo rm -rf root/.cache/*
rm -rf ~/.thumbnails/*
rm -rf ~/.cache/thumbnails/*

echo "Cleaning crash dumps and systemd coredumps"
sudo rm -rf /var/crash/*
sudo rm -rf /var/lib/systemd/coredump/
rm -rf ~/.local/share/Trash/*
sudo rm -rf /root/.local/share/Trash/*

echo "Clearing old history files..."
rm -f ~/.python_history
sudo rm -f /root/.python_history
rm -f ~/.bash_history
sudo rm -f /root/.bash_history

echo "Vacuuming journal logs"
sudo journalctl --rotate --vacuum-size=1 --flush --sync -q
sudo rm -rf --preserve-root -- /run/log/journal/* /var/log/journal/* 2>/dev/null || :
sudo systemd-tmpfiles --clean >/dev/null

echo "Running fstrim"
sudo fstrim -a --quiet-unsupported

echo "Removind old log files"
sudo find -O3 /var/log/ -name "*.log" -type f -mtime +3 -delete
sudo find -O3 /var/crash/ -name "core.*" -type f -mtime +3 -delete
sudo find -O3 /var/cache/apt/ -name "*.bin" -type f -mtime +3 -delete

sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
echo "System clean-up complete."

echo "Clearing DietPi..."
sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null
sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null




