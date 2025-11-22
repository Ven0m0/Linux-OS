#!/usr/bin/env bash
# Optimized: 2025-11-19 - Applied bash optimization techniques
# Source common library
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ $SCRIPT_DIR == "${BASH_SOURCE[0]}" ]] && SCRIPT_DIR="."
cd "$SCRIPT_DIR" || exit 1
SCRIPT_DIR="$PWD"

#============ Core Functions ============
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

export LC_ALL=C LANG=C LANGUAGE=C

#============ Colors ============
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m'

#============ Helper Functions ============
has(){ command -v "$1" &>/dev/null; }
log(){ printf '%b\n' "$*"; }
msg(){ printf '%b%s%b\n' "$GRN" "$*" "$DEF"; }
warn(){ printf '%b%s%b\n' "$YLW" "$*" "$DEF"; }
die(){ printf '%b%s%b\n' "$RED" "$*" "$DEF" >&2; exit "${2:-1}"; }

# Determine the device mounted at root
ROOT_DEV=$(findmnt -n -o SOURCE /)

# Check the filesystem type of the root device
FSTYPE=$(findmnt -n -o FSTYPE /)

# If the filesystem is ext4, execute the tune2fs command
if [[ $FSTYPE == "ext4" ]]; then
  log "Root filesystem is ext4 on $ROOT_DEV"
  sudo tune2fs -O fast_commit "$ROOT_DEV"
else
  log "Root filesystem is not ext4 (detected: $FSTYPE). Skipping tune2fs."
fi

sudo balooctl6 disable && sudo balooctl6 purge

log "Applying Breeze Dark theme"
kwriteconfig6 --file ~/.config/kdeglobals --group General --key ColorScheme "BreezeDark"
plasma-apply-desktoptheme breeze-dark

sed -i 's/opacity = 0.8/opacity = 1.0/' "$HOME/.config/alacritty/alacritty.toml"

# Locale
locale -a | grep -q '^en_US\.utf8$' && { export LANG='en_US.UTF-8' LANGUAGE='en_US'; } || export LANG='C.UTF-8'

sudo curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Linux-Settings/etc/sysctl.d/99-tweak-settings.conf -o /etc/sysctl.d/99-tweak-settings.conf

log "Debloat and fixup"
sudo pacman -Rns cachyos-v4-mirrorlist --noconfirm || :
sudo pacman -Rns cachy-browser --noconfirm || :

log "install basher from https://github.com/basherpm/basher"
curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash

# https://github.com/YurinDoctrine/arch-linux-base-setup
log "Optimize writes to the disk"
for svc in journald coredump; do
  file=/etc/systemd/${svc}.conf
  # always ensure Storage=none
  kvs=(Storage=none)
  # only for journald: also Seal=no and Audit=no
  [[ $svc == journald ]] && kvs+=(Seal=no Audit=no)
  for kv in "${kvs[@]}"; do
    if grep -qE "^#*${kv%%=*}=" "$file"; then
      sudo sed -i -E "s|^#*${kv%%=*}=.*|$kv|" "$file"
    else
      log "$kv" | sudo tee -a "$file" >/dev/null
    fi
  done
done

log "Disable bluetooth autostart"
sudo sed -i -e 's/AutoEnable.*/AutoEnable = false/' /etc/bluetooth/main.conf
sudo sed -i -e 's/FastConnectable.*/FastConnectable = false/' /etc/bluetooth/main.conf
sudo sed -i -e 's/ReconnectAttempts.*/ReconnectAttempts = 1/' /etc/bluetooth/main.conf
sudo sed -i -e 's/ReconnectIntervals.*/ReconnectIntervals = 1/' /etc/bluetooth/main.conf

log "Reduce systemd timeout"
sudo sed -i -e 's/#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=5s/g' /etc/systemd/system.conf
sudo sed -i -e 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=5s/g' /etc/systemd/system.conf

## Set zram
sudo sed -i -e 's/#ALGO.*/ALGO=lz4/g' /etc/default/zramswap
sudo sed -i -e 's/PERCENT.*/PERCENT=25/g' /etc/default/zramswap

## Flush bluetooth
sudo rm -rfd /var/lib/bluetooth/*

log "Disable plymouth"
sudo systemctl mask plymouth-read-write.service >/dev/null 2>&1
sudo systemctl mask plymouth-start.service >/dev/null 2>&1
sudo systemctl mask plymouth-quit.service >/dev/null 2>&1
sudo systemctl mask plymouth-quit-wait.service >/dev/null 2>&1

## Disable file indexer
balooctl suspend
balooctl disable
balooctl purge
sudo systemctl disable plasma-baloorunner
for dir in "$HOME" "$HOME"/*/; do touch "$dir/.metadata_never_index" "$dir/.noindex" "$dir/.nomedia" "$dir/.trackerignore"; done

log "Enable write cache"
log "write back" | sudo tee /sys/block/*/queue/write_cache

log "Disable logging services"
sudo systemctl mask systemd-update-utmp.service >/dev/null 2>&1
sudo systemctl mask systemd-update-utmp-runlevel.service >/dev/null 2>&1
sudo systemctl mask systemd-update-utmp-shutdown.service >/dev/null 2>&1
sudo systemctl mask systemd-journal-flush.service >/dev/null 2>&1
sudo systemctl mask systemd-journal-catalog-update.service >/dev/null 2>&1
sudo systemctl mask systemd-journald-dev-log.socket >/dev/null 2>&1
sudo systemctl mask systemd-journald-audit.socket >/dev/null 2>&1
log "Disable speech-dispatcher"
sudo systemctl disable speech-dispatcher
sudo systemctl --global disable speech-dispatcher
log "Disable smartmontools"
sudo systemctl disable smartmontools
sudo systemctl --global disable smartmontools
log "Disable systemd radio service/socket"
sudo systemctl disable systemd-rfkill.service
sudo systemctl --global disable systemd-rfkill.service
sudo systemctl disable systemd-rfkill.socket
sudo systemctl --global disable systemd-rfkill.socket
log "Enable dbus-broker"
sudo systemctl enable dbus-broker.service
sudo systemctl --global enable dbus-broker.service
log "Disable wait online service"
log "[connectivity]
enabled=false" | sudo tee /etc/NetworkManager/conf.d/20-connectivity.conf
sudo systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1

log "Disable GPU polling"
log "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf

## Improve preload
sudo sed -i -e 's/sortstrategy =.*/sortstrategy = 0/' /etc/preload.conf

# Disable pacman logging.
sudo sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf

sudo timedatectl set-timezone Europe/Berlin

# Don't reserve space man-pages, locales, licenses.
log "Remove useless companies"
find /usr/share/doc/ -depth -type f ! -name copyright -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.gz' -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.pdf' -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.tex' -exec sudo rm -f {} + || :
find /usr/share/doc/ -depth -type d -empty -exec sudo rmdir {} + || :
sudo rm -rfd /usr/share/groff/* /usr/share/info/* /usr/share/lintian/* \
  /usr/share/linda/* /var/cache/man/* /usr/share/man/* /usr/share/X11/locale/!\(en_GB\)
sudo rm -rfd /usr/share/locale/!\(en_GB\)
yay -Rcc --noconfirm man-pages

log "Flush flatpak database"
sudo flatpak uninstall --unused --delete-data -y
sudo flatpak repair

log "Compress fonts"
woff2_compress /usr/share/fonts/opentype/*/*ttf
woff2_compress /usr/share/fonts/truetype/*/*ttf
## Optimize font cache
fc-cache -rfv
## Optimize icon cache
gtk-update-icon-cache

log "Clean crash log"
sudo rm -rfd /var/crash/*
log "Clean archived journal"
sudo journalctl --rotate --vacuum-time=0.1
sudo sed -i -e 's/^#ForwardToSyslog=yes/ForwardToSyslog=no/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#ForwardToKMsg=yes/ForwardToKMsg=no/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#ForwardToConsole=yes/ForwardToConsole=no/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#ForwardToWall=yes/ForwardToWall=no/' /etc/systemd/journald.conf
log "Compress log files"
sudo sed -i -e 's/^#Compress=yes/Compress=yes/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#compress/compress/' /etc/logrotate.conf
log "kernel.core_pattern=/dev/null" | sudo tee /etc/sysctl.d/50-coredump.conf

#--Disable crashes
sudo sed -i -e 's/^#DumpCore=.*/DumpCore=no/' /etc/systemd/system.conf
sudo sed -i -e 's/^#CrashShell=.*/CrashShell=no/' /etc/systemd/system.conf
sudo sed -i -e 's/^#DumpCore=.*/DumpCore=no/' /etc/systemd/user.conf
sudo sed -i -e 's/^#CrashShell=.*/CrashShell=no/' /etc/systemd/user.conf

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

# Disable USB autosuspend to prevent peripheral disconnection issues
if [[ ! -f /etc/modprobe.d/disable-usb-autosuspend.conf ]]; then
  echo "options usbcore autosuspend=-1" | sudo tee /etc/modprobe.d/disable-usb-autosuspend.conf
fi

#--Update CA
sudo update-ca-trust

sudo sh -c 'touch /etc/modprobe.d/ignore_ppc.conf; log "options processor ignore_ppc=1" >/etc/modprobe.d/ignore_ppc.conf'

sudo sh -c 'touch /etc/modprobe.d/nvidia.conf; log "options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0 NVreg_DynamicPowerManagement=0x02" >/etc/modprobe.d/nvidia.conf'

log "options vfio_pci disable_vga=1
                   options cec debug=0
                   options kvm mmu_audit=0
                   options kvm ignore_msrs=1
                   options kvm report_ignored_msrs=0
                   options kvm kvmclock_periodic_sync=1
                   options nfs enable_ino64=1
                   options libata allow_tpm=0
                   options libata ignore_hpa=0
                   options libahci ignore_sss=1
                   options libahci skip_host_reset=1
                   options uhci-hcd debug=0
                   options usbcore usbfs_snoop=0
                   options usbcore autosuspend=10" | sudo tee /etc/modprobe.d/misc.conf

log "bfq
      ntsync
      tcp_bbr
      zram" | sudo tee /etc/modprobe.d/modules.conf


vscode_json_set(){
  local prop=$1 val=$2
  has python3 || { log "Skipping VSCode setting (no python3): $prop"; return; }
  python3 <<EOF
from pathlib import Path
import os, json, sys
property_name='$prop'
target=json.loads('$val')
home_dir=f'/home/{os.getenv("SUDO_USER",os.getenv("USER"))}'
settings_files=[
  f'{home_dir}/.config/Code/User/settings.json',
  f'{home_dir}/.config/VSCodium/User/settings.json',
  f'{home_dir}/.config/Void/User/settings.json',
  f'{home_dir}/.var/app/com.visualstudio.code/config/Code/User/settings.json'
]
for sf in settings_files:
  file=Path(sf)
  if not file.is_file(): continue
  content=file.read_text()
  if not content.strip(): content='{}'
  try: obj=json.loads(content)
  except json.JSONDecodeError: continue
  if property_name in obj and obj[property_name]==target: continue
  obj[property_name]=target
  file.write_text(json.dumps(obj,indent=2))
EOF
}
  # VSCode privacy settings
  vscode_json_set 'telemetry.telemetryLevel' '"off"'
  vscode_json_set 'telemetry.enableTelemetry' 'false'
  vscode_json_set 'telemetry.enableCrashReporter' 'false'
  vscode_json_set 'workbench.enableExperiments' 'false'
  vscode_json_set 'update.mode' '"none"'
  vscode_json_set 'update.channel' '"none"'
  vscode_json_set 'update.showReleaseNotes' 'false'
  vscode_json_set 'npm.fetchOnlinePackageInfo' 'false'
  vscode_json_set 'git.autofetch' 'false'
  vscode_json_set 'workbench.settings.enableNaturalLanguageSearch' 'false'
  vscode_json_set 'typescript.disableAutomaticTypeAcquisition' 'false'
  vscode_json_set 'workbench.experimental.editSessions.enabled' 'false'
  vscode_json_set 'workbench.experimental.editSessions.autoStore' 'false'
  vscode_json_set 'workbench.editSessions.autoResume' 'false'
  vscode_json_set 'workbench.editSessions.continueOn' 'false'
  vscode_json_set 'extensions.autoUpdate' 'false'
  vscode_json_set 'extensions.autoCheckUpdates' 'false'
  vscode_json_set 'extensions.showRecommendationsOnlyOnDemand' 'true'
