#!/usr/bin/env bash

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
rm -f ~/.mozilla/firefox/Crash\ Reports/*
# Clear Flatpak cache
rm -rf ~/.var/app/*/cache/*
sudo rm -rf /var/tmp/flatpak-cache-*
rm -rf ~/.cache/flatpak/system-cache/*
rm -rf ~/.local/share/flatpak/system-cache/*
rm -rf ~/.var/app/*/data/Trash/*
echo '--- Clear Snap cache'
rm -f ~/snap/*/*/.cache/*
sudo rm -rf /var/lib/snapd/cache/*
rm -rf ~/snap/*/*/.local/share/Trash/*
# Clear thumbnails
rm -rf ~/.thumbnails/*
rm -rf ~/.cache/thumbnails/*
# Clear system logs
sudo rm -f /var/log/pacman.log
sudo journalctl --vacuum-time=1s
sudo rm -rf /run/log/journal/*
sudo rm -rf /var/log/journal/*
# Terminal
rm -f ~/.local/share/fish/fish_history
sudo rm -f /root/.local/share/fish/fish_history
rm -f ~/.config/fish/fish_history
sudo rm -f /root/.config/fish/fish_history
rm -f ~/.zsh_history
sudo rm -f /root/.zsh_history
rm -f ~/.bash_history
sudo rm -f /root/.bash_history
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
# Wine
rm -rf ~/.wine/drive_c/windows/temp/*
rm -rf ~/.cache/wine/
rm -rf ~/.cache/winetricks/
# My stuff
# https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Installing_only_content_in_required_languages
sudo rm -rf /usr/share/doc/*
sudo rm -rf /usr/share/help/*
sudo rm -rf /usr/share/gtk-doc/*
sudo find /var/log -type f -name *.old -print0 | xargs -0 sudo rm -- >/dev/null 2>&1

# pacman -S profile-cleaner
sudo paccache -rk0 -q
sudo pacman -Scc --noconfirm
# sudo pacman -Qdtq | pacman -Rns -
sudo pacman -Rns $(pacman -Qtdq)
flatpak uninstall --unused
sudo fstrim -av --quiet-unsupported

# Use Bleachbit if available
if which bleachbit >/dev/null 2>&1; then
    bleachbit -c --preset
    sudo -E bleachbit -c --preset
fi
