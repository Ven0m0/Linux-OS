#!/usr/bin/env bash
export LC_ALL=C LANG=C
shopt -s nullglob globstar execfail
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#──────────── Helpers ────────────────────
has(){ local x="${1:?no argument}"; x=$(command -v -- "$x") &>/dev/null || return 1; [[ -x $x ]] || return 1; }
hasname(){ local x="${1:?no argument}"; x=$(type -P -- "$x" 2>/dev/null) || return 1; printf '%s\n' "${x##*/}"; }
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
  "$LBLU"   # Light Blue
  "$PNK"    # Pink
  "$BWHT"   # White
  "$PNK"    # Pink
  "$LBLU"   # Light Blue
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
#============ Main ====================
[[ $EUID -ne 0 ]] && sudo -v
export HOME="/home/${SUDO_USER:-$USER}"
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
# Capture usage before cleanup
read -r used_human pct < <(df -h --output=used,pcent -- / 2>/dev/null | awk 'NR==2{print $1, $2}')
DUB="$used_human $pct"
SPACE="$(sudo du -sh / 2>/dev/null | cut -f1)"

# Clearing dns cache and release/renew dhcp
has dhclient && dhclient -r
sudo resolvectl flush-caches >/dev/null

# Pacman cleanup
sudo pacman -Rns "$(pacman -Qdtq 2>/dev/null)" --noconfirm >/dev/null
sudo pacman -Scc --noconfirm
sudo paccache -rk0 -q
uv cache prune -q; uv cache clean -q
# Cargo
if command -v cargo-cache &>/dev/null; then
  cargo cache -efg
  cargo cache -efg trim --limit 1B
  cargo cache -efg clean-unref
fi

# https://github.com/sghimi/QuickOptimization
# Kill all processes using excessive amounts of CPU
for i in $(ps aux --sort=-%cpu | awk '{if($3>50.0) print $2}' | tail -n +2); do 
  kill -9 $i; 
done

# Clear the system's swap space
swapoff -a && swapon -a

# Remove old log files
find -O3 /var/log/ -name "*.log" -type f -mtime +7 -delete

# Remove old core dump files
find -O3 /var/crash/ -name "core.*" -type f -mtime +7 -delete
# Remove old package files
find -O3 /var/cache/apt/ -name "*.bin" -mtime +7 -delete

# Clear cache
sudo find -O3 ~/.cache -type f -mtime +1 -print -delete >/dev/null
sudo find -O3 ~/.cache -type d -empty -print -delete >/dev/null
sudo find -O3 ~/.cache -type d -empty -print -delete >/dev/null
sudo systemd-tmpfiles --clean >/dev/null
sudo rm -rf --preserve-root -- "/var/cache/"*
sudo rm -rf --preserve-root -- "/tmp/"*
sudo rm -rf --preserve-root -- "/var/tmp/"*
sudo rm -rf --preserve-root -- "/var/crash/"*
sudo rm -rf --preserve-root -- "/var/lib/systemd/coredump/"*
rm -rf --preserve-root -- "${HOME}/.cache/"*
sudo rm -rf --preserve-root -- "/root/.cache/"*
rm -rf --preserve-root -- "${HOME}/.var/app/"*/cache/*
rm -f --preserve-root -- "${HOME}/.config/Trolltech.conf" || :
kbuildsycoca6 --noincremental || :

# Empty global trash
rm -rf --preserve-root -- "${HOME}/.local/share/Trash/"*
sudo rm -rf --preserve-root -- "/root/.local/share/Trash/"*

# Flatpak
if command -v flatpak &> /dev/null; then
  flatpak uninstall --unused --delete-data -y --noninteractive
else
  echo 'Skipping because "flatpak" is not found.'
fi
sudo rm -rf --preserve-root -- /var/tmp/flatpak-cache-*
rm -rf --preserve-root -- "${HOME}/.cache/flatpak/system-cache/"*
rm -rf --preserve-root -- "${HOME}/.local/share/flatpak/system-cache/"*
rm -rf --preserve-root -- ${HOME}/.var/app/*/data/Trash/*
# Clear thumbnails
rm -rf --preserve-root -- "${HOME}/.thumbnails/"*

# Clear system logs
sudo rm -f --preserve-root -- "/var/log/pacman.log"
sudo journalctl --rotate --vacuum-size=1 --flush --sync -q
sudo rm -rf --preserve-root -- /run/log/journal/* /var/log/journal/* 2>/dev/null || :
sudo rm -rf --preserve-root -- {/root,/home/*}/.local/share/zeitgeist/*
# Home cleaning
rm -f --preserve-root -- "${HOME}/.wget-hsts" "${HOME}/.curl-hsts" "${HOME}/.lesshst" "${HOME}/nohup.out" "${HOME}/token"
# Shell history
rm -f --preserve-root -- "${HOME}/.local/share/fish/fish_history" "${HOME}/.config/fish/fish_history" "${HOME}/.zsh_history" "${HOME}/.bash_history" "${HOME}/.history"
sudo rm -f --preserve-root -- "/root/.local/share/fish/fish_history" "/root/.config/fish/fish_history" "/root/.zsh_history" "/root/.bash_history" "/root/.history"

# LibreOffice
rm -f --preserve-root -- "${HOME}/.config/libreoffice/4/user/registrymodifications.xcu" "${HOME}/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu"
rm -f --preserve-root -- "${HOME}/snap/libreoffice/*/.config/libreoffice/4/user/registrymodifications.xcu"

# Steam
rm -rf --preserve-root -- "${HOME}/.local/share/Steam/appcache/"*
rm -rf --preserve-root -- "${HOME}/snap/steam/common/.cache/"*
rm -rf --preserve-root -- "${HOME}/snap/steam/common/.local/share/Steam/appcache/"*
rm -rf --preserve-root -- "${HOME}/.var/app/com.valvesoftware.Steam/cache/"*
rm -rf --preserve-root -- "${HOME}/.var/app/com.valvesoftware.Steam/data/Steam/appcache/"*

# NVIDIA
sudo rm -rf --preserve-root -- "${HOME}/.nv/ComputeCache/"*
# Python
#rm -f ${HOME}/.python_history
echo '--- Disable Python history for future interactive commands'
history_file="${HOME}/.python_history"
[[ ! -f $history_file ]] && { touch "$history_file" echo "Created $history_file."; }
sudo chattr +i "$(realpath "$history_file")"

# Firefox
rm -rf --preserve-root -- "${HOME}/.mozilla/firefox/*/bookmarkbackups" >/dev/null
rm -rf --preserve-root -- "${HOME}/.mozilla/firefox/*/saved-telemetry-pings" >/dev/null
rm -rf --preserve-root -- "${HOME}/.mozilla/firefox/*/sessionstore-logs" >/dev/null
rm -rf --preserve-root -- "${HOME}/.mozilla/firefox/*/sessionstore-backups" >/dev/null
rm -f --preserve-root -- "${HOME}/.cache/mozilla/"* >/dev/null
rm -f --preserve-root -- "${HOME}/.var/app/org.mozilla.firefox/cache/"* >/dev/null
rm -f --preserve-root -- "${HOME}/snap/firefox/common/.cache/"* >/dev/null
# Delete files matching pattern: "~/.mozilla/firefox/*/crashes/*" "~/.mozilla/firefox/*/crashes/events/*"
if command -v python3 &> /dev/null; then
  python3 <<EOF
import glob
import os
path = '~/.mozilla/firefox/*/crashes/*'
expanded_path = os.path.expandvars(os.path.expanduser(path))
print(f'Deleting files matching pattern: {expanded_path}')
paths = glob.glob(expanded_path)
if not paths:
  print('Skipping, no paths found.')
for path in paths:
  if not os.path.isfile(path):
    print(f'Skipping folder: "{path}".')
    continue
  os.remove(path)
  print(f'Successfully delete file: "{path}".')
print(f'Successfully deleted {len(paths)} file(s).')
EOF
  python3 <<EOF
import glob
import os
path = '~/.mozilla/firefox/*/crashes/events/*'
expanded_path = os.path.expandvars(os.path.expanduser(path))
print(f'Deleting files matching pattern: {expanded_path}')
paths = glob.glob(expanded_path)
if not paths:
  print('Skipping, no paths found.')
for path in paths:
  if not os.path.isfile(path):
    print(f'Skipping folder: "{path}".')
    continue
  os.remove(path)
  print(f'Successfully delete file: "{path}".')
print(f'Successfully deleted {len(paths)} file(s).')
EOF
fi

# Wine
rm -f --preserve-root -- "${HOME}/.wine/drive_c/windows/temp/"* >/dev/null
rm -f --preserve-root --  "${HOME}/.cache/wine/"* >/dev/null
rm -f --preserve-root -- "${HOME}/.cache/winetricks/"* >/dev/null
# GTK
rm -f --preserve-root -- "/.recently-used.xbel" "${HOME}/.local/share/recently-used.xbel" >/dev/null
rm -f --preserve-root -- "${HOME}/snap/*/*/.local/share/recently-used.xbel" >/dev/null
rm -f --preserve-root -- "${HOME}/.var/app/*/data/recently-used.xbel" >/dev/null
# KDE
rm -rf --preserve-root -- "${HOME}/.local/share/RecentDocuments/*.desktop" >/dev/null
rm -rf --preserve-root -- "${HOME}/.kde/share/apps/RecentDocuments/*.desktop" >/dev/null
rm -rf --preserve-root -- "${HOME}/.kde4/share/apps/RecentDocuments/*.desktop" >/dev/null
rm -rf --preserve-root -- "${HOME}/.var/app/*/data/*.desktop" >/dev/null
rm -rf --preserve-root -- "${HOME}/.local/share/Steam/appcache/"* >/dev/null

# Trim disks
sudo fstrim -a --quiet-unsupported; sudo fstrim -A --quiet-unsupported

# Font cache
sudo fc-cache -f >/dev/null

if command -v sdk &>/dev/null; then
  sdk flush tmp
fi

# BleachBit if available
if command -v bleachbit &>/dev/null; then
  LC_ALL=C LANG=C bleachbit -c --preset >/dev/null
  if command -v xhost &>/dev/null; then
    xhost si:localuser:root >/dev/null; xhost si:localuser:"$USER" >/dev/null
    LC_ALL=C LANG=C sudo bleachbit -c --preset >/dev/null
  elif command -v pkexec &>/dev/null; then
    LC_ALL=C LANG=C pkexec bleachbit -c --preset >/dev/null
  else
    echo "Error: neither xhost (for sudo) nor pkexec available. Cannot run BleachBit."
  fi
else
  echo "BleachBit is not installed, skipping."
fi

echo "System cleaned!"
# Capture usage after cleanup
read -r used_space_after pct_after < <(df -h --output=used,pcent -- / 2>/dev/null | awk 'NR==2{print $1, $2}')
DUA="$used_space_after $pct_after"
echo "==> Disk usage before cleanup ${DUB}"
echo
echo "==> Disk usage after cleanup ${DUA}"

echo 'space before/after'
echo "$SPACE"
sudo du -sh / 2>/dev/null | cut -f1
