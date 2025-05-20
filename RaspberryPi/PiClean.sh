#!/usr/bin/env bash

sudo apt clean && sudo apt autoclean && sudo apt-get -y autoremove --purge
sudo rm -rfv /var/lib/apt/lists/*
sudo pip cache purge
rm -rf /var/cache/*
rm -rfv ~/.cache/*
sudo rm -rfv root/.cache/*
rm -rfv ~/.thumbnails/*
rm -rfv ~/.cache/thumbnails/*
sudo rm -rfv /tmp/*
sudo rm -rfv /var/tmp/*
sudo rm -rf /var/crash/*
sudo rm -rf /var/lib/systemd/coredump/
rm -rfv ~/.local/share/Trash/*
sudo rm -rfv /root/.local/share/Trash/*
rm -fv ~/.python_history
sudo rm -fv /root/.python_history
rm -fv ~/.bash_history
sudo rm -fv /root/.bash_history
if ! command -v 'journalctl' &> /dev/null; then
  echo 'Skipping because "journalctl" is not found.'
else
  sudo journalctl --vacuum-time=1s
fi
sudo rm -rfv /run/log/journal/*
sudo rm -rfv /var/log/journal/*
sudo fstrim -av --quiet-unsupported
sudo dietpi-logclear
