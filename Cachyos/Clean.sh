#!/bin/bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C LANG=C
shopt -s nullglob globstar

sudo -v

sudo sync

# Pacman cleanup
sudo pacman -Rns $(pacman -Qdtq) --noconfirm || :
sudo pacman -Scc --noconfirm || :
sudo paccache -rk0 -q || :
uv cache clean || :
# Cargo
if command -v cargo-cache &>/dev/null; then
    cargo cache -efg || :
    cargo-cache -efg trim --limit 1B || :
    cargo cache -efg clean-unref || :
fi

# Clear cache
sudo systemd-tmpfiles --clean 
sudo rm -rf /var/cache/*
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo rm -rf /var/crash/*
sudo rm -rf /var/lib/systemd/coredump/
rm -rf ~/.cache/*
sudo rm -rf /root/.cache/*
rm -rf ~/.var/app/*/cache/*
# rm ~/.config/Trolltech.conf || :
kbuildsycoca6 --noincremental || :

# Empty global trash
rm -rf ~/.local/share/Trash/*
sudo rm -rf /root/.local/share/Trash/*

# Flatpak
if command -v flatpak &> /dev/null; then
  flatpak uninstall --unused --noninteractive
else
  echo 'Skipping because "flatpak" is not found.'
fi
sudo rm -rf /var/tmp/flatpak-cache-*
rm -rf ~/.cache/flatpak/system-cache/*
rm -rf ~/.local/share/flatpak/system-cache/*
rm -rf ~/.var/app/*/data/Trash/*

# Clear thumbnails
rm -rf ~/.thumbnails/*
rm -rf ~/.cache/thumbnails/*

# Clear system logs
sudo rm -f /var/log/pacman.log || :
sudo journalctl --rotate -q || :
sudo journalctl --vacuum-time=1s -q || :
#sudo rm -rf /run/log/journal/* /var/log/journal/* || :
#sudo rm -rf {/root,/home/*}/.local/share/zeitgeist || :

# Shell history
rm -f ~/.local/share/fish/fish_history ~/.config/fish/fish_history ~/.zsh_history ~/.bash_history ~/.history
sudo rm -f /root/.local/share/fish/fish_history /root/.config/fish/fish_history /root/.zsh_history /root/.bash_history /root/.history

# LibreOffice
rm -f ~/.config/libreoffice/4/user/registrymodifications.xcu
rm -f ~/snap/libreoffice/*/.config/libreoffice/4/user/registrymodifications.xcu
rm -f ~/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu

# Steam
rm -rf ~/.local/share/Steam/appcache/*
rm -rf ~/snap/steam/common/.cache/*
rm -rf ~/snap/steam/common/.local/share/Steam/appcache/*
rm -rf ~/.var/app/com.valvesoftware.Steam/cache/*
rm -rf ~/.var/app/com.valvesoftware.Steam/data/Steam/appcache/*

# Python
rm -f ~/.python_history
sudo rm -f /root/.python_history

# Firefox
rm -rf ~/.cache/mozilla/*
rm -rf ~/.var/app/org.mozilla.firefox/cache/*
rm -rf ~/snap/firefox/common/.cache/*
rm -f ~/.mozilla/firefox/Crash\ Reports/*
rm -rf ~/.var/app/org.mozilla.firefox/.mozilla/firefox/Crash\ Reports/*
rm -rf ~/snap/firefox/common/.mozilla/firefox/Crash\ Reports/**

# Wine
rm -rf ~/.wine/drive_c/windows/temp/*
rm -rf ~/.cache/wine/
rm -rf ~/.cache/winetricks/

# GTK
rm -f ~/.local/share/recently-used.xbel*
rm -f ~/snap/*/*/.local/share/recently-used.xbel
rm -f ~/.var/app/*/data/recently-used.xbel

# KDE
rm -rf ~/.local/share/RecentDocuments/*.desktop
rm -rf ~/.kde/share/apps/RecentDocuments/*.desktop
rm -rf ~/.kde4/share/apps/RecentDocuments/*.desktop
rm -f ~/snap/*/*/.local/share/*.desktop
rm -rf ~/.var/app/*/data/*.desktop

# TLDR cache
tldr -c && sudo tldr -c || :

# Trim disks
sudo fstrim -a --quiet-unsupported



# BleachBit if available
#if command -v bleachbit &>/dev/null; then
#    bleachbit -c --preset && sudo -E bleachbit -c --preset
#else
#    echo "bleachbit is not installed, skipping."
#fi
bleachbit -c --preset && sudo -E bleachbit -c --preset

sync; echo 3 | sudo tee /proc/sys/vm/drop_caches
echo "System cleaned!"
