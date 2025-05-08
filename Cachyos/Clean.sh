echo '--- Clear system-wide cache'
rm -rf /var/cache/*
sudo rm -rfv /tmp/*
sudo rm -rfv /var/tmp/*
sudo rm -rfv /var/crash/*
sudo rm -rfv /var/lib/systemd/coredump/
echo '--- Empty trash'
# Empty global trash
rm -rfv ~/.local/share/Trash/*
sudo rm -rfv /root/.local/share/Trash/*
echo '--- Clear user-specific cache'
rm -rfv ~/.cache/*
sudo rm -rfv root/.cache/*
rm -fv ~/.mozilla/firefox/Crash\ Reports/*
echo '--- Clear Flatpak cache'
rm -rfv ~/.var/app/*/cache/*
sudo rm -rfv /var/tmp/flatpak-cache-*
rm -rfv ~/.cache/flatpak/system-cache/*
rm -rfv ~/.local/share/flatpak/system-cache/*
rm -rfv ~/.var/app/*/data/Trash/*
echo '--- Clear Snap cache'
rm -fv ~/snap/*/*/.cache/*
sudo rm -rfv /var/lib/snapd/cache/*
rm -rfv ~/snap/*/*/.local/share/Trash/*
echo '--- Clear thumbnails (icon cache)'
rm -rfv ~/.thumbnails/*
rm -rfv ~/.cache/thumbnails/*
echo '--- Clear system logs (`journald`)'
sudo journalctl --vacuum-time=1s
sudo rm -rfv /run/log/journal/*
sudo rm -rfv /var/log/journal/*
# Terminal
rm -fv ~/.local/share/fish/fish_history
sudo rm -fv /root/.local/share/fish/fish_history
rm -fv ~/.config/fish/fish_history
sudo rm -fv /root/.config/fish/fish_history
rm -fv ~/.zsh_history
sudo rm -fv /root/.zsh_history
rm -fv ~/.bash_history
sudo rm -fv /root/.bash_history
# LibreOffice
rm -f ~/.config/libreoffice/4/user/registrymodifications.xcu
rm -fv ~/snap/libreoffice/*/.config/libreoffice/4/user/registrymodifications.xcu
rm -fv ~/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu
# Steam
rm -rfv ~/.local/share/Steam/appcache/*
rm -rfv ~/snap/steam/common/.cache/*
rm -rfv ~/snap/steam/common/.local/share/Steam/appcache/*
rm -rfv ~/.var/app/com.valvesoftware.Steam/cache/*
rm -rfv ~/.var/app/com.valvesoftware.Steam/data/Steam/appcache/*
# Python
rm -fv ~/.python_history
sudo rm -fv /root/.python_history
# Wine
rm -rfv ~/.wine/drive_c/windows/temp/*
rm -rfv ~/.cache/wine/
rm -rfv ~/.cache/winetricks/
# My stuff
profile-cleaner f
paccache -r
pacman -Scc
sudo pacman -Qdtq | pacman -Rns -
# pacman -Qqd | pacman -Rsu --print -
