#!/usr/bin/env bash
#──────────── Setup ────────────────────
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/cleaning.sh"

# Setup environment
setup_environment

# Initialize working directory
init_workdir

#──────────── Sudo ────────────────────
load_dietpi_globals
suexec="$(get_sudo_cmd)" || exit 1
init_sudo
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
sudo find -O3 /var/log/ -name "*.log" -type f -mtime +3 -delete
sudo find -O3 /var/crash/ -name "core.*" -type f -mtime +3 -delete
sudo find -O3 /var/cache/apt/ -name "*.bin" -type f -mtime +3 -delete

sync
echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
echo "System clean-up complete."

echo "Clearing DietPi..."
run_dietpi_cleanup
