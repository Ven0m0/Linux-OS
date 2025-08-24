#!/usr/bin/env bash
#──────────── Setup ────────────────────
shopt -s nullglob globstar
export LC_ALL=C LANG=C
WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd $WORKDIR
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
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove --purge -y
sudo apt purge ?config-files
echo "Cleaning leftover config files"
dpkg -l | awk '/^rc/ { print $2 }' | xargs sudo apt purge -y

echo "orphan removal"
if command -v deborphan &>/dev/null; then
  sudo deborphan | xargs sudo apt-get -y remove --purge --auto-remove
else
  echo 'Skipping deborphan — not installed.'
fi

uv cache prune -q; uv cache clean -q

sudo rm -rf /var/lib/apt/lists/*
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
rm -fv ~/.python_history
sudo rm -fv /root/.python_history
rm -fv ~/.bash_history
sudo rm -fv /root/.bash_history

echo "Vacuuming journal logs"
sudo rm -f /var/log/pacman.log
sudo journalctl --rotate -q && sudo journalctl --vacuum-time=1s -q

echo "Running fstrim"
sudo rm -rf /run/log/journal/*
sudo rm -rf /var/log/journal/*
sudo fstrim -a --quiet-unsupported

echo "Removind old log files"
sudo find /var/log -type f -name "*.log" -exec rm -f {} \;

sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
echo "System clean-up complete."

echo "Clearing DietPi logs..."
sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null
