#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
LC_ALL=C LANG=C
hash rm sudo 
sync;sudo -v

clear
echo
echo " ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗     ███████╗ ██████╗██████╗ ██╗██████╗ ████████╗"
echo "██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝     ██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝"
echo "██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗    ███████╗██║     ██████╔╝██║██████╔╝   ██║   "
echo "██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║    ╚════██║██║     ██╔══██╗██║██╔═══╝    ██║   "
echo "╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝    ███████║╚██████╗██║  ██║██║██║        ██║   "
echo " ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝     ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   "
echo 

DISK_USAGE_BEFORE=$(df -h)

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
rm -rf $HOME/.cache/*
sudo rm -rf /root/.cache/*
rm -rf $HOME/.var/app/*/cache/*
rm $HOME/.config/Trolltech.conf || :
kbuildsycoca6 --noincremental || :

# Empty global trash
rm -rf $HOME/.local/share/Trash/*
sudo rm -rf /root/.local/share/Trash/*

# Flatpak
if command -v flatpak &> /dev/null; then
  flatpak uninstall --unused --noninteractive
else
  echo 'Skipping because "flatpak" is not found.'
fi
sudo rm -rf /var/tmp/flatpak-cache-*
rm -rf $HOME/.cache/flatpak/system-cache/*
rm -rf $HOME/.local/share/flatpak/system-cache/*
rm -rf $HOME/.var/app/*/data/Trash/*

# Clear thumbnails
rm -rf $HOME/.thumbnails/*
rm -rf $HOME/.cache/thumbnails/*

# Clear system logs
sudo rm -f /var/log/pacman.log || :
sudo journalctl --rotate -q || :
sudo journalctl --vacuum-time=1s -q || :
sudo rm -rf /run/log/journal/* /var/log/journal/* || :
sudo rm -rf {/root,/home/*}/.local/share/zeitgeist || :

# Shell history
rm -f $HOME/.local/share/fish/fish_history $HOME/.config/fish/fish_history $HOME/.zsh_history $HOME/.bash_history $HOME/.history
sudo rm -f /root/.local/share/fish/fish_history /root/.config/fish/fish_history /root/.zsh_history /root/.bash_history /root/.history

# LibreOffice
rm -f $HOME/.config/libreoffice/4/user/registrymodifications.xcu
rm -f $HOME/snap/libreoffice/*/.config/libreoffice/4/user/registrymodifications.xcu
rm -f $HOME/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu

# Steam
rm -rf $HOME/.local/share/Steam/appcache/*
rm -rf $HOME/snap/steam/common/.cache/*
rm -rf $HOME/snap/steam/common/.local/share/Steam/appcache/*
rm -rf $HOME/.var/app/com.valvesoftware.Steam/cache/*
rm -rf $HOME/.var/app/com.valvesoftware.Steam/data/Steam/appcache/*

# Python
rm -f $HOME/.python_history
sudo rm -f /root/.python_history

# Firefox
rm -rf $HOME/.cache/mozilla/*
rm -rf $HOME/.var/app/org.mozilla.firefox/cache/*
rm -rf $HOME/snap/firefox/common/.cache/*
rm -rf $HOME/.mozilla/firefox/Crash\ Reports/*
rm -rf $HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/Crash\ Reports/*
rm -rf $HOME/snap/firefox/common/.mozilla/firefox/Crash\ Reports/**

# Wine
rm -rf $HOME/.wine/drive_c/windows/temp/*
rm -rf $HOME/.cache/wine/
rm -rf $HOME/.cache/winetricks/

# GTK
rm -f $HOME/.local/share/recently-used.xbel*
rm -f $HOME/snap/*/*/.local/share/recently-used.xbel
rm -f $HOME/.var/app/*/data/recently-used.xbel

# KDE
rm -rf $HOME/.local/share/RecentDocuments/*.desktop
rm -rf $HOME/.kde/share/apps/RecentDocuments/*.desktop
rm -rf $HOME/.kde4/share/apps/RecentDocuments/*.desktop
rm -f $HOME/snap/*/*/.local/share/*.desktop
rm -rf $HOME/.var/app/*/data/*.desktop

# TLDR cache
tldr -c && sudo tldr -c || :

# Trim disks
sudo fstrim -a --quiet-unsupported || :

# Clearing dns cache
systemd-resolve --flush-caches

# BleachBit if available
#if command -v bleachbit &>/dev/null; then
#    bleachbit -c --preset && sudo -E bleachbit -c --preset
#else
#    echo "bleachbit is not installed, skipping."
#fi
bleachbit -c --preset && sudo -E bleachbit -c --preset || :

sync; echo 3 | sudo tee /proc/sys/vm/drop_caches || :
echo "System cleaned!"

echo "==> Disk usage before cleanup ${DISK_USAGE_BEFORE}"

echo "==> Disk usage after cleanup"
df -h
