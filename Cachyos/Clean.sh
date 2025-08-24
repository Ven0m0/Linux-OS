#!/usr/bin/env bash
shopt -s nullglob globstar; set -u
export LC_ALL=C LANG=C
#──────────── Color & Effects ────────────
BLK='\e[30m' # Black
RED='\e[31m' # Red
GRN='\e[32m' # Green
YLW='\e[33m' # Yellow
BLU='\e[34m' # Blue
MGN='\e[35m' # Magenta
CYN='\e[36m' # Cyan
WHT='\e[37m' # White
DEF='\e[0m'  # Reset to default
BLD='\e[1m'  #Bold
#─────────────────────────────────────────
printf '\033[2J\033[3J\033[1;1H'; printf '\e]2;%s\a' "Updates"
p() { printf "%s\n" "$@"; }
pe() { printf "%b\n" "$@"; }
# Ascii art banner
colors=(
  $'\033[38;5;117m'  # Light Blue
  $'\033[38;5;218m'  # Pink
  $'\033[38;5;15m'   # White
  $'\033[38;5;218m'  # Pink
  $'\033[38;5;117m'  # Light Blue
)
reset=$'\033[0m'
banner=$(command cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ 
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ 
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
)
# Split banner into an array
IFS=$'\n' read -r -d '' -a banner_lines <<< "$banner"
# Total lines
lines=${#banner_lines[@]}
# Loop through each line and apply scaled trans flag colors
for i in "${!banner_lines[@]}"; do
  # Map line index to color index (scaled to 5 colors)
  color_index=$(( i * 5 / lines ))
  printf "%s%s%s\n" "${colors[color_index]}" "${banner_lines[i]}" "$reset"
done

sudo -v
DISK_USAGE_BEFORE=$(df -hl --output=used,pcent | head -n 2 -q | tail -n 1 -q)

#──────────── Safe optimal privilege tool ────────────────────
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { p "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v || :
#─────────────────────────────────────────

# Pacman cleanup
sudo pacman -Rns $(pacman -Qdtq) --noconfirm -q
sudo pacman -Scc --noconfirm
sudo paccache -rk0 -q
uv cache prune -q; uv cache clean -q
# Cargo
if command -v cargo-cache &>/dev/null; then
    cargo cache -efg || :
    cargo-cache -efg trim --limit 1B || :
    cargo cache -efg clean-unref || :
fi

# Clear cache
sudo systemd-tmpfiles --clean >/dev/null
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
sudo rm -rf $HOME/.local/share/Trash/*
sudo rm -rf /root/.local/share/Trash/*

# Flatpak
if command -v flatpak &> /dev/null; then
  flatpak uninstall --unused --delete-data -y --noninteractive
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

# NVIDIA
sudo rm -rf $HOME/.nv/ComputeCache/*

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
sudo tldr -c >/dev/null || :

# Trim disks
sudo fstrim -a --quiet-unsupported >/dev/null || :
sudo fstrim / --quiet-unsupported >/dev/null || :

# Clearing dns cache
systemd-resolve --flush-caches >/dev/null

# Font cache
fc-cache -f >/dev/null

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
