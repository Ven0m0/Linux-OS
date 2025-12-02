#!/usr/bin/env bash
# Optimized: 2025-11-21 - Applied bash optimization techniques
#──────────── Setup ────────────────────

# Source shared libraries
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/core.sh
source "$SCRIPT_DIR/../lib/core.sh"
# shellcheck source=lib/debian.sh
source "$SCRIPT_DIR/../lib/debian.sh"
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
sudo apt-get purge '?config-files' 2>/dev/null || :
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
echo "Removing old log files"
sudo find /var/log/ -name "*.log" -type f -mtime +3 -delete
sudo find /var/crash/ -name "core.*" -type f -mtime +3 -delete
sudo find /var/cache/apt/ -name "*.bin" -type f -mtime +3 -delete

sync
echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
echo "System clean-up complete."
echo "Clearing DietPi..."
run_dietpi_cleanup
