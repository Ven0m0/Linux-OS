#!/usr/bin/env bash
export LC_ALL=C LANG=C; set -u
shopt -s nullglob globstar
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#──────────── Helpers ────────────────────
has(){ command -v -- "$1" &>/dev/null; } # Check for command
hasname(){ local x=$(type -P -- "$1") || return; printf '%s\n' "${x##*/}"; } # Get basename of command
p(){ printf '%s\n' "$*" 2>/dev/null || :; } # Print-echo
pe(){ printf '%b\n' "$*" 2>/dev/null || :; } # Print-echo for color
#──────────── Banner ────────────────────
banner=$(cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ 
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ 
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
)
# Split banner into array
mapfile -t banner_lines <<< "$banner"
lines=${#banner_lines[@]}
# Trans flag gradient sequence (top→bottom) using 256 colors for accuracy
flag_colors=(
  $LBLU  # Light Blue
  $PNK   # Pink
  $BWHT  # White
  $PNK   # Pink
  $LBLU  # Light Blue
)
segments=${#flag_colors[@]}
# If banner is trivially short, just print without dividing by (lines-1)
if (( lines <= 1 )); then
  for line in "${banner_lines[@]}"; do
    printf "%s%s%s\n" "${flag_colors[0]}" "$line" "$DEF"
  done
else
  for i in "${!banner_lines[@]}"; do
    # Map line index proportionally into 0..(segments-1)
    segment_index=$(( i * (segments - 1) / (lines - 1) ))
    (( segment_index >= segments )) && segment_index=$((segments - 1))
    printf "%s%s%s\n" "${flag_colors[segment_index]}" "${banner_lines[i]}" "$DEF"
  done
fi
#──────────── Safe optimal privilege tool ────────────────────
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { p "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v || :

# Pacman cleanup
sudo pacman -Rns $(pacman -Qdtq) --noconfirm &>/dev/null
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

read -r used_space_after pct_after < <(df -h --output=used,pcent -- "$mp" | awk 'NR==2{print $1, $2}')
DUA="$used_space_after $pct_after"
echo "==> Disk usage before cleanup ${DUB}"
echo
echo "==> Disk usage after cleanup ${DUA}"
