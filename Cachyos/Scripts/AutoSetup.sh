#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
sudo -v

# Determine the device mounted at root
ROOT_DEV=$(findmnt -n -o SOURCE /)

# Check the filesystem type of the root device
FSTYPE=$(findmnt -n -o FSTYPE /)

# If the filesystem is ext4, execute the tune2fs command
if [[ "$FSTYPE" == "ext4" ]]; then
    echo "Root filesystem is ext4 on $ROOT_DEV"
    sudo tune2fs -O fast_commit "$ROOT_DEV"
else
    echo "Root filesystem is not ext4 (detected: $FSTYPE). Skipping tune2fs."
fi

sudo balooctl6 disable && sudo balooctl6 purge

echo "Applying Breeze Dark theme"
kwriteconfig6 --file ~/.config/kdeglobals --group General --key ColorScheme "BreezeDark"
plasma-apply-desktoptheme breeze-dark

sed -i 's/opacity = 0.8/opacity = 1.0/' "$HOME/.config/alacritty/alacritty.toml"

sudo curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Linux-Settings/etc/sysctl.d/99-tweak-settings.conf -o /etc/sysctl.d/99-tweak-settings.conf


echo "Debloat and fixup"
sudo pacman -Rns cachyos-v4-mirrorlist --noconfirm || true
sudo pacman -Rns cachy-browser --noconfirm || true


echo "install basher from https://github.com/basherpm/basher"
curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash

# https://github.com/YurinDoctrine/arch-linux-base-setup
echo -e "Optimize writes to the disk"
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
      echo "$kv" | sudo tee -a "$file" >/dev/null
    fi
  done
done

echo -e "Disable bluetooth autostart"
sudo sed -i -e 's/AutoEnable.*/AutoEnable = false/' /etc/bluetooth/main.conf
sudo sed -i -e 's/FastConnectable.*/FastConnectable = false/' /etc/bluetooth/main.conf
sudo sed -i -e 's/ReconnectAttempts.*/ReconnectAttempts = 1/' /etc/bluetooth/main.conf
sudo sed -i -e 's/ReconnectIntervals.*/ReconnectIntervals = 1/' /etc/bluetooth/main.conf

echo -e "Reduce systemd timeout"
sudo sed -i -e 's/#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=5s/g' /etc/systemd/system.conf
sudo sed -i -e 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=5s/g' /etc/systemd/system.conf

## Set zram
sudo sed -i -e 's/#ALGO.*/ALGO=lz4/g' /etc/default/zramswap
sudo sed -i -e 's/PERCENT.*/PERCENT=25/g' /etc/default/zramswap

# ------------------------------------------------------------------------

## Flush bluetooth
sudo rm -rfd /var/lib/bluetooth/*

echo -e "Disable plymouth"
sudo systemctl mask plymouth-read-write.service >/dev/null 2>&1
sudo systemctl mask plymouth-start.service >/dev/null 2>&1
sudo systemctl mask plymouth-quit.service >/dev/null 2>&1
sudo systemctl mask plymouth-quit-wait.service >/dev/null 2>&1

## Disable file indexer
balooctl suspend
balooctl disable
balooctl purge
sudo systemctl disable plasma-baloorunner
for dir in $HOME $HOME/*/; do touch "$dir/.metadata_never_index" "$dir/.noindex" "$dir/.nomedia" "$dir/.trackerignore"; done

echo -e "Enable write cache"
echo -e "write back" | sudo tee /sys/block/*/queue/write_cache

echo -e "Disable logging services"
sudo systemctl mask systemd-update-utmp.service >/dev/null 2>&1
sudo systemctl mask systemd-update-utmp-runlevel.service >/dev/null 2>&1
sudo systemctl mask systemd-update-utmp-shutdown.service >/dev/null 2>&1
sudo systemctl mask systemd-journal-flush.service >/dev/null 2>&1
sudo systemctl mask systemd-journal-catalog-update.service >/dev/null 2>&1
sudo systemctl mask systemd-journald-dev-log.socket >/dev/null 2>&1
sudo systemctl mask systemd-journald-audit.socket >/dev/null 2>&1
echo -e "Disable speech-dispatcher"
sudo systemctl disable speech-dispatcher
sudo systemctl --global disable speech-dispatcher
echo -e "Disable smartmontools"
sudo systemctl disable smartmontools
sudo systemctl --global disable smartmontools
echo -e "Disable systemd radio service/socket"
sudo systemctl disable systemd-rfkill.service
sudo systemctl --global disable systemd-rfkill.service
sudo systemctl disable systemd-rfkill.socket
sudo systemctl --global disable systemd-rfkill.socket
echo -e "Enable dbus-broker"
sudo systemctl enable dbus-broker.service
sudo systemctl --global enable dbus-broker.service
echo -e "Disable wait online service"
echo -e "[connectivity]
enabled=false" | sudo tee /etc/NetworkManager/conf.d/20-connectivity.conf
sudo systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1

echo -e "Disable GPU polling"
echo -e "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf

## Improve preload
sudo sed -i -e 's/sortstrategy =.*/sortstrategy = 0/' /etc/preload.conf

# Disable pacman logging.
sudo sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf

sudo timedatectl set-timezone Europe/Berlin 

# Don't reserve space man-pages, locales, licenses.
echo -e "Remove useless companies"
find /usr/share/doc/ -depth -type f ! -name copyright | xargs sudo rm -f || true
find /usr/share/doc/ | grep '\.gz' | xargs sudo rm -f
find /usr/share/doc/ | grep '\.pdf' | xargs sudo rm -f
find /usr/share/doc/ | grep '\.tex' | xargs sudo rm -f
find /usr/share/doc/ -empty | xargs sudo rmdir || true
sudo rm -rfd /usr/share/groff/* /usr/share/info/* /usr/share/lintian/* \
    /usr/share/linda/* /var/cache/man/* /usr/share/man/* /usr/share/X11/locale/!\(en_GB\)
sudo rm -rfd /usr/share/locale/!\(en_GB\)
yay -Rcc --noconfirm man-pages

echo -e "Flush flatpak database"
sudo flatpak uninstall --unused --delete-data -y
sudo flatpak repair

echo -e "Compress fonts"
woff2_compress /usr/share/fonts/opentype/*/*ttf
woff2_compress /usr/share/fonts/truetype/*/*ttf
## Optimize font cache
fc-cache -rfv
## Optimize icon cache
gtk-update-icon-cache

echo -e "Clean crash log"
sudo rm -rfd /var/crash/*
echo -e "Clean archived journal"
sudo journalctl --rotate --vacuum-time=0.1
sudo sed -i -e 's/^#ForwardToSyslog=yes/ForwardToSyslog=no/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#ForwardToKMsg=yes/ForwardToKMsg=no/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#ForwardToConsole=yes/ForwardToConsole=no/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#ForwardToWall=yes/ForwardToWall=no/' /etc/systemd/journald.conf
echo -e "Compress log files"
sudo sed -i -e 's/^#Compress=yes/Compress=yes/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#compress/compress/' /etc/logrotate.conf
echo -e "kernel.core_pattern=/dev/null" | sudo tee /etc/sysctl.d/50-coredump.conf

#--Disable crashes
sudo sed -i -e 's/^#DumpCore=.*/DumpCore=no/' /etc/systemd/system.conf
sudo sed -i -e 's/^#CrashShell=.*/CrashShell=no/' /etc/systemd/system.conf
sudo sed -i -e 's/^#DumpCore=.*/DumpCore=no/' /etc/systemd/user.conf
sudo sed -i -e 's/^#CrashShell=.*/CrashShell=no/' /etc/systemd/user.conf

#--Update CA
sudo update-ca-trust

doas sh -c 'touch /etc/modprobe.d/ignore_ppc.conf; echo "options processor ignore_ppc=1" >/etc/modprobe.d/ignore_ppc.conf'

doas sh -c 'touch /etc/modprobe.d/nvidia.conf; echo "options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0 NVreg_DynamicPowerManagement=0x02" >/etc/modprobe.d/nvidia.conf'

echo "options vfio_pci disable_vga=1
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
                   options usbcore autosuspend=10" | doas tee /etc/modprobe.d/misc.conf

echo "bfq
      ntsync
      tcp_bbr
      zram" | doas tee /etc/modprobe.d/modules.conf

        
