#!/usr/bin/env bash
export LC_ALL=C LANG=C; set -u
shopt -s nullglob globstar; sync
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
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v 2>/dev/null || :
export HOME="/home/${SUDO_USER:-$USER}"

read -r used_human pct < <(df -h --output=used,pcent -- "$mp" | awk 'NR==2{print $1, $2}')

# Pacman cleanup
"$suexec" pacman -Rns $(pacman -Qdtq) --noconfirm &>/dev/null
"$suexec" pacman -Scc --noconfirm
"$suexec" paccache -rk0 -q
uv cache prune -q; uv cache clean -q
# Cargo
if command -v cargo-cache &>/dev/null; then
  cargo cache -efg || :
  cargo cache -efg trim --limit 1B || :
  cargo cache -efg clean-unref || :
fi

# Clear cache
"$suexec" systemd-tmpfiles --clean >/dev/null
"$suexec" rm -rf /var/cache/*
"$suexec" rm -rf /tmp/*
"$suexec" rm -rf /var/tmp/*
"$suexec" rm -rf /var/crash/*
"$suexec" rm -rf /var/lib/systemd/coredump/
rm -rf $HOME/.cache/*
"$suexec" rm -rf /root/.cache/*
rm -rf $HOME/.var/app/*/cache/*
rm $HOME/.config/Trolltech.conf || :
kbuildsycoca6 --noincremental || :

# Empty global trash
"$suexec" rm -rf $HOME/.local/share/Trash/*
"$suexec" rm -rf /root/.local/share/Trash/*

# Flatpak
if command -v flatpak &> /dev/null; then
  flatpak uninstall --unused --delete-data -y --noninteractive
else
  echo 'Skipping because "flatpak" is not found.'
fi
"$suexec" rm -rf /var/tmp/flatpak-cache-*
rm -rf $HOME/.cache/flatpak/system-cache/*
rm -rf $HOME/.local/share/flatpak/system-cache/*
rm -rf $HOME/.var/app/*/data/Trash/*

# Clear thumbnails
rm -rf $HOME/.thumbnails/*
rm -rf $HOME/.cache/thumbnails/*

# Clear system logs
"$suexec" rm -f /var/log/pacman.log || :
"$suexec" journalctl --rotate -q || :
"$suexec" journalctl --vacuum-time=1s -q || :
"$suexec" rm -rf /run/log/journal/* /var/log/journal/* || :
"$suexec" rm -rf {/root,/home/*}/.local/share/zeitgeist || :

# Shell history
rm -f $HOME/.local/share/fish/fish_history $HOME/.config/fish/fish_history $HOME/.zsh_history $HOME/.bash_history $HOME/.history
"$suexec" rm -f /root/.local/share/fish/fish_history /root/.config/fish/fish_history /root/.zsh_history /root/.bash_history /root/.history

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
"$suexec" rm -rf $HOME/.nv/ComputeCache/*

# Python
#rm -f $HOME/.python_history
echo '--- Disable Python history for future interactive commands'
history_file="$HOME/.python_history"
if [[ ! -f $history_file ]]; then
  command touch -- "$history_file"
  echo "Created $history_file."
fi
"$suexec" chattr +i "$(realpath $history_file)"

# Firefox
rm -rf $HOME/.cache/mozilla/* >/dev/null || :
rm -rf $HOME/.var/app/org.mozilla.firefox/cache/* >/dev/null || :
rm -rf $HOME/snap/firefox/common/.cache/* >/dev/null || :
rm -rf $HOME/.mozilla/firefox/Crash\ Reports/* >/dev/null || :
rm -rf $HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/Crash\ Reports/* >/dev/null || :
rm -rf $HOME/snap/firefox/common/.mozilla/firefox/Crash\ Reports/** >/dev/null || :
# Delete files matching pattern: "~/.mozilla/firefox/*/crashes/*"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
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
fi
# Delete files matching pattern: "~/.mozilla/firefox/*/crashes/events/*"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
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
rm -rf $HOME/.wine/drive_c/windows/temp/* >/dev/null || :
rm -rf $HOME/.cache/wine/ >/dev/null || :
rm -rf $HOME/.cache/winetricks/ >/dev/null || :

# GTK
rm -f /.recently-used.xbel || :
rm -f $HOME/.local/share/recently-used.xbel* >/dev/null || :
rm -f $HOME/snap/*/*/.local/share/recently-used.xbel >/dev/null || :
rm -f $HOME/.var/app/*/data/recently-used.xbel >/dev/null || :

# KDE
rm -rf $HOME/.local/share/RecentDocuments/*.desktop >/dev/null || :
rm -rf $HOME/.kde/share/apps/RecentDocuments/*.desktop >/dev/null || :
rm -rf $HOME/.kde4/share/apps/RecentDocuments/*.desktop >/dev/null || :
rm -f $HOME/snap/*/*/.local/share/*.desktop >/dev/null || :
rm -rf $HOME/.var/app/*/data/*.desktop >/dev/null || :

# TLDR cache
"$suexec" tldr -c >/dev/null || :

# Trim disks
"$suexec" fstrim -a --quiet-unsupported &>/dev/null || :

# Clearing dns cache
"$suexec" systemd-resolve --flush-caches >/dev/null

# Font cache
"$suexec" fc-cache -f >/dev/null

# BleachBit if available
if command -v bleachbit &>/dev/null; then
  bleachbit -c --preset >/dev/null
  if command -v xhost &>/dev/null; then
    "$suexec" bleachbit -c --preset >/dev/null
  elif command -v pkexec &>/dev/null; then
    pkexec bleachbit -c --preset >/dev/null
  else
    echo "Error: neither xhost (for sudo) nor pkexec available. Cannot run BleachBit."
  fi
else
  echo "BleachBit is not installed, skipping."
fi

sync; echo 3 | "$suexec" tee /proc/sys/vm/drop_caches &>/dev/null || :
echo "System cleaned!"

read -r used_space_after pct_after < <(df -h --output=used,pcent -- / | awk 'NR==2{print $1, $2}')
DUA="$used_space_after $pct_after"
echo "==> Disk usage before cleanup ${DUB}"
echo
echo "==> Disk usage after cleanup ${DUA}"
