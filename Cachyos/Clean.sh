#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
  script_path=$([[ "$0" = /* ]] && echo "$0" || echo "$PWD/${0#./}")
  sudo "$script_path" || (
    echo 'Administrator privileges are required.'
    exit 1
  )
  exit 0
fi
export HOME="/home/${SUDO_USER:-${USER}}"

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
# Clear Snap cache
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
# Clear Firefox crash reports
echo '--- Clear Firefox crash reports'
# Global installation
rm -fv ~/.mozilla/firefox/Crash\ Reports/*
# Flatpak installation
rm -rfv ~/.var/app/org.mozilla.firefox/.mozilla/firefox/Crash\ Reports/*
# Snap installation
rm -rfv ~/snap/firefox/common/.mozilla/firefox/Crash\ Reports/*
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
# Delete files matching pattern: "~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/crashes/*"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
  python3 <<EOF
import glob
import os
path = '~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/crashes/*'
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
# Delete files matching pattern: "~/snap/firefox/common/.mozilla/firefox/*/crashes/*"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
  python3 <<EOF
import glob
import os
path = '~/snap/firefox/common/.mozilla/firefox/*/crashes/*'
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
# Delete files matching pattern: "~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/crashes/events/*"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
  python3 <<EOF
import glob
import os
path = '~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/crashes/events/*'
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
# Delete files matching pattern: "~/snap/firefox/common/.mozilla/firefox/*/crashes/events/*"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
  python3 <<EOF
import glob
import os
path = '~/snap/firefox/common/.mozilla/firefox/*/crashes/events/*'
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
# Clear Firefox "Multi-Account Containers" data
echo '--- Clear Firefox "Multi-Account Containers" data'
# Delete files matching pattern: "~/.mozilla/firefox/*/containers.json"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
  python3 <<EOF
import glob
import os
path = '~/.mozilla/firefox/*/containers.json'
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
# Delete files matching pattern: "~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/containers.json"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
  python3 <<EOF
import glob
import os
path = '~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/containers.json'
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
# Delete files matching pattern: "~/snap/firefox/common/.mozilla/firefox/*/containers.json"
if ! command -v 'python3' &> /dev/null; then
  echo 'Skipping because "python3" is not found.'
else
  python3 <<EOF
import glob
import os
path = '~/snap/firefox/common/.mozilla/firefox/*/containers.json'
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
rm -rf ~/.wine/drive_c/windows/temp/*
rm -rf ~/.cache/wine/
rm -rf ~/.cache/winetricks/
# My stuff
# https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Installing_only_content_in_required_languages
sudo rm -rf /usr/share/doc/*
sudo rm -rf /usr/share/help/*
sudo rm -rf /usr/share/gtk-doc/*
sudo find /var/log -type f -name *.old -print0 | xargs -0 sudo rm -- >/dev/null 2>&1
sudo paccache -rk0 -q
sudo pacman -Scc --noconfirm
# sudo pacman -Qdtq | pacman -Rns -
yes | sudo pacman -Rns $(pacman -Qtdq)
flatpak uninstall --unused
sudo fstrim -av --quiet-unsupported

# Use Bleachbit if available
if command -v bleachbit >/dev/null 2>&1; then
    bleachbit -c --preset
    sudo -E bleachbit -c --preset
else
    echo "bleachbit is not installed, skipping."
fi
