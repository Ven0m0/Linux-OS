#!/usr/bin/env bash

sudo -v

# Clear system-wide cache
rm -rf /var/cache/*
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo rm -rf /var/crash/*
sudo rm -rf /var/lib/systemd/coredump/
# Empty global trash
rm -rf ~/.local/share/Trash/*
sudo rm -rf /root/.local/share/Trash/*
# Clear user-specific cache
rm -rf ~/.cache/*
sudo rm -rf root/.cache/*
rm -rf ~/.var/app/*/cache/*
# Flatpak
if ! command -v 'flatpak' &> /dev/null; then
  echo 'Skipping because "flatpak" is not found.'
else
  flatpak uninstall --unused --noninteractive
fi    
sudo rm -rf /var/tmp/flatpak-cache-*
rm -rf ~/.cache/flatpak/system-cache/*
rm -rf ~/.local/share/flatpak/system-cache/*
rm -rf ~/.var/app/*/data/Trash/*
# Clear Snap cache
rm -f ~/snap/*/*/.cache/*
sudo rm -rf /var/lib/snapd/cache/*
rm -rf ~/snap/*/*/.local/share/Trash/*
echo '--- Remove old Snap packages'
if ! command -v 'snap' &> /dev/null; then
  echo 'Skipping because "snap" is not found.'
else
  snap list --all | while read name version rev tracking publisher notes; do
  if [[ $notes = *disabled* ]]; then
    sudo snap remove "$name" --revision="$rev";
  fi
done
fi
# Clear thumbnails
rm -rf ~/.thumbnails/*
rm -rf ~/.cache/thumbnails/*
# Clear system logs
sudo rm -f /var/log/pacman.log
sudo journalctl --vacuum-time=1s
sudo rm -rf /run/log/journal/*
sudo rm -rf /var/log/journal/*
sudo rm -rfv {/root,/home/*}/.local/share/zeitgeist
# Terminal
rm -f ~/.local/share/fish/fish_history
sudo rm -f /root/.local/share/fish/fish_history
rm -f ~/.config/fish/fish_history
sudo rm -f /root/.config/fish/fish_history
rm -f ~/.zsh_history
sudo rm -f /root/.zsh_history
rm -f ~/.bash_history
sudo rm -f /root/.bash_history
rm -fv ~/.history
sudo rm -fv /root/.history
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
rm -rfv ~/.cache/mozilla/*
rm -rfv ~/.var/app/org.mozilla.firefox/cache/*
rm -rfv ~/snap/firefox/common/.cache/*
rm -fv ~/.mozilla/firefox/Crash\ Reports/*
rm -rfv ~/.var/app/org.mozilla.firefox/.mozilla/firefox/Crash\ Reports/*
rm -rfv ~/snap/firefox/common/.mozilla/firefox/Crash\ Reports/**
# Wine
rm -rf ~/.wine/drive_c/windows/temp/*
rm -rf ~/.cache/wine/
rm -rf ~/.cache/winetricks/
# GTK
rm -fv /.recently-used.xbel
rm -fv ~/.local/share/recently-used.xbel*
rm -fv ~/snap/*/*/.local/share/recently-used.xbel
rm -fv ~/.var/app/*/data/recently-used.xbel
# KDE
rm -rfv ~/.local/share/RecentDocuments/*.desktop
rm -rfv ~/.kde/share/apps/RecentDocuments/*.desktop
rm -rfv ~/.kde4/share/apps/RecentDocuments/*.desktop
rm -fv ~/snap/*/*/.local/share/*.desktop
rm -rfv ~/.var/app/*/data/*.desktop
# My stuff
# https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Installing_only_content_in_required_languages
sudo pacman -Rns $(pacman -Qdtq) --noconfirm
sudo pacman -Scc --noconfirm && sudo paccache -rk0 -q
sudo fstrim -av --quiet-unsupported
# Use Bleachbit if available
if command -v bleachbit >/dev/null 2>&1; then
    bleachbit -c --preset
    sudo -E bleachbit -c --preset
else
    echo "bleachbit is not installed, skipping."
fi
