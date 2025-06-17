#!/usr/bin/bash

sudo -v

echo "Cleaning apt cache"
sudo apt clean
sudo apt autoclean
sudo apt-get autoremove --purge -y

echo "Cleaning leftover config files"
dpkg -l | grep '^rc' | awk '{print $2}' | xargs sudo apt purge -y || true
dpkg -l | awk '/^rc/ { print $2 }' | xargs sudo apt purge -y

echo "orphan removal"
if command -v deborphan &>/dev/null; then
  sudo deborphan | xargs sudo apt-get -y remove --purge
else
  echo 'Skipping deborphan — not installed.'
fi

echo "Cleaning pip cache"
if command -v pip &>/dev/null; then
  sudo pip cache purge || true
fi

sudo rm -rf /var/lib/apt/lists/*
echo "Removing common cache directories and trash"
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
rm -rf /var/cache/*
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
sudo journalctl --vacuum-time=1s

echo "Running fstrim"
sudo rm -rf /run/log/journal/*
sudo rm -rf /var/log/journal/*
sudo fstrim -av --quiet-unsupported || true

echo "Clearing DietPi logs..."
sudo dietpi-logclear 2 || true

echo "System clean-up complete."
