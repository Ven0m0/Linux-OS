#!/usr/bin/bash

sudo -v
sync

echo "Cleaning apt cache"
sudo apt clean
sudo apt autoclean
sudo apt-get autoremove --purge -y

echo "Cleaning leftover config files"
dpkg -l | awk '/^rc/ { print $2 }' | xargs sudo apt purge -y

echo "orphan removal"
if command -v deborphan &>/dev/null; then
  sudo deborphan | xargs sudo apt-get -y remove --purge --auto-remove
else
  echo 'Skipping deborphan — not installed.'
fi

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
sudo journalctl --rotate -q || true
sudo journalctl --vacuum-time=1s -q

echo "Running fstrim"
sudo rm -rf /run/log/journal/*
sudo rm -rf /var/log/journal/*
sudo fstrim -a --quiet-unsupported

sync; echo 3 | sudo tee /proc/sys/vm/drop_caches
echo "System clean-up complete."

echo "Clearing DietPi logs..."
sudo -E dietpi-logclear 2 || sudo -E ./boot/dietpi/func/dietpi-logclear 2
