#!/usr/bin/env bash

# Setup environment
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'

# Install packages without user interaction
export DEBIAN_FRONTEND=noninteractive

# Configure dpkg to exclude documentation and locales
configure_dpkg_nodoc() {
  local dpkg_config='path-exclude /usr/share/doc/*
path-exclude /usr/share/help/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
# we need to keep copyright files for legal reasons
path-include /usr/share/doc/*/copyright'

  echo "$dpkg_config" | sudo tee /etc/dpkg/dpkg.cfg.d/01_nodoc >/dev/null
  echo "Configured dpkg to exclude documentation in future installations"
}

# Remove system documentation files
clean_documentation() {
  echo "Removing documentation files..."
  find /usr/share/doc/ -depth -type f ! -name copyright -delete 2>/dev/null || :
  find /usr/share/doc/ -name '*.gz' -delete 2>/dev/null || :
  find /usr/share/doc/ -name '*.pdf' -delete 2>/dev/null || :
  find /usr/share/doc/ -name '*.tex' -delete 2>/dev/null || :
  find /usr/share/doc/ -type d -empty -delete 2>/dev/null || :

  echo "Removing man pages and related files..."
  sudo rm -rf /usr/share/groff/* /usr/share/info/* /usr/share/lintian/* \
    /usr/share/linda/* /var/cache/man/* /usr/share/man/* 2>/dev/null || :
}

echo "Install Pi-Hole"
curl -sSL https://install.pi-hole.net | sudo bash

echo "Install PiKISS <3"
curl -sSL https://git.io/JfAPE | bash

echo Alternative install
git clone https://github.com/jmcerrejon/PiKISS.git && cd PiKISS || exit
./piKiss.sh

git config --global http.sslVerify false
git pull

# TODO: might break DietPi
# echo "Replace Bash shell with Dash shell"
# sudo dpkg-reconfigure dash

echo "Install PiApps-terminal_bash-edition"
echo "https://github.com/Itai-Nelken/PiApps-terminal_bash-edition"
curl -ssfL https://raw.githubusercontent.com/Itai-Nelken/PiApps-terminal_bash-edition/main/install.sh | bash
pi-apps update -y

echo -e 'APT::Acquire::Retries "5";
Acquire::Queue-Mode "access";
Acquire::Languages "none";
APT::Acquire::ForceIPv4 "true";
APT::Get::AllowUnauthenticated "true";
Acquire::CompressionTypes::Order:: "gz";
APT { Get { Assume-Yes "true"; Fix-Broken "true"; Fix-Missing "true"; List-Cleanup "true"; };};
APT::Acquire::Max-Parallel-Downloads "5";' | sudo tee /etc/apt/apt.conf.d/99parallel
#Acquire::CompressionTypes::lz4 "lz4";

echo -e 'APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
APT::Periodic::Update-Package-Lists "1";
Unattended-Upgrade::MinimalSteps "true";' | sudo tee /etc/apt/apt.conf.d/50-unattended-upgrades

# Disable APT terminal logging
echo -e 'Dir::Log::Terminal "";' | sudo tee /etc/apt/apt.conf.d/01disable-log

configure_dpkg_nodoc

## DPKG keep current versions of configs
echo -e 'DPkg::Options {
   "--force-confdef";
};' | sudo tee /etc/apt/apt.conf.d/71debconf

echo -e "LC_ALL=C" | sudo tee -a /etc/environment

# Don't reserve space for man-pages, locales, licenses.
echo -e "Remove unnecessary documentation packages"
sudo apt-get remove --purge *texlive* -yy 2>/dev/null || :
clean_documentation
# Keep only en_GB locale
sudo rm -rf /usr/share/X11/locale/!\(en_GB\) 2>/dev/null || :
sudo rm -rf /usr/share/locale/!\(en_GB\) 2>/dev/null || :

echo -e "Disable wait online service"
echo -e "[connectivity]
enabled=false" | sudo tee /etc/NetworkManager/conf.d/20-connectivity.conf
sudo systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1

echo -e "Disable SELINUX"
echo -e "SELINUX=disabled
SELINUXTYPE=minimum" | sudo tee /etc/selinux/config
sudo setenforce 0

## Some powersavings
echo "options vfio_pci disable_vga=1
options cec debug=0
options kvm mmu_audit=0
options kvm ignore_msrs=1
options kvm report_ignored_msrs=0
options kvm kvmclock_periodic_sync=1
options nfs enable_ino64=1
options pstore backend=null
options libata allow_tpm=0
options libata ignore_hpa=0
options libahci ignore_sss=1
options libahci skip_host_reset=1
options snd_hda_intel power_save=1
options snd_ac97_codec power_save=1
options uhci-hcd debug=0
options usbhid mousepoll=20 kbpoll=20 jspoll=20
options usb-storage quirks=p
options usbcore usbfs_snoop=0
options usbcore autosuspend=10" | sudo tee /etc/modprobe.d/misc.conf
echo -e "min_power" | sudo tee /sys/class/scsi_host/*/link_power_management_policy
echo 1 | sudo tee /sys/module/snd_hda_intel/parameters/power_save
echo -e "auto" | sudo tee /sys/bus/{i2c,pci}/devices/*/power/control
sudo powertop --auto-tune && sudo powertop --auto-tune
sudo cpupower frequency-set -g powersave
sudo cpupower set --perf-bias 9
sudo sensors-detect --auto

#--Optimize udev
sudo sed -i -e 's/^#udev_log=info/udev_log=err/' /etc/udev/udev.conf
sudo sed -i -e 's/^#exec_delay=/exec_delay=0/' /etc/udev/udev.conf

## Disable file indexer
balooctl suspend
balooctl disable
balooctl purge
sudo systemctl disable plasma-baloorunner
for dir in "$HOME" "$HOME"/*/; do touch "$dir/.metadata_never_index" "$dir/.noindex" "$dir/.nomedia" "$dir/.trackerignore"; done

echo -e "Enable write cache"
echo -e "write back" | sudo tee /sys/block/*/queue/write_cache
# Optimize device detection - use findmnt instead of df|grep|awk
root_dev=$(findmnt -n -o SOURCE /)
home_dev=$(findmnt -n -o SOURCE /home 2>/dev/null || echo "$root_dev")
sudo tune2fs -o journal_data_writeback "$root_dev"
sudo tune2fs -O ^has_journal "$root_dev"
[[ -n $home_dev && $home_dev != "$root_dev" ]] && {
  sudo tune2fs -o journal_data_writeback "$home_dev"
  sudo tune2fs -O ^has_journal "$home_dev"
}
echo -e "Enable fast commit"
sudo tune2fs -O fast_commit "$root_dev"
[[ -n $home_dev && $home_dev != "$root_dev" ]] && sudo tune2fs -O fast_commit "$home_dev"

echo -e "Compress .local/bin"
upx /home/"$USER"/.local/bin/*

echo -e "Improve I/O throughput"
echo 32 | sudo tee /sys/block/sd*[!0-9]/queue/iosched/fifo_batch
echo 32 | sudo tee /sys/block/mmcblk*/queue/iosched/fifo_batch
echo 32 | sudo tee /sys/block/nvme[0-9]*/queue/iosched/fifo_batch

echo -e "Disable systemd foo service"
sudo systemctl disable foo.service
sudo systemctl --global disable foo.service

## Improve wifi and ethernet
if ip -o link | grep -q wlan; then
  echo -e "options iwlwifi power_save=1
options iwlmvm power_scheme=3" | sudo tee /etc/modprobe.d/wlan.conf
  echo -e "options rfkill default_state=0 master_switch_mode=0" | sudo tee /etc/modprobe.d/wlanextra.conf
  sudo ethtool -K wlan0 gro on
  sudo ethtool -K wlan0 gso on
  sudo ethtool -c wlan0
  sudo iwconfig wlan0 txpower auto
  sudo iwpriv wlan0 set_power 5
else
  sudo ethtool -s eth0 wol d
  sudo ethtool -K eth0 gro off
  sudo ethtool -K eth0 gso off
  sudo ethtool -C eth0 adaptive-rx on
  sudo ethtool -C eth0 adaptive-tx on
  sudo ethtool -c eth0
fi

echo -e "Enable HDD write caching"
sudo hdparm -A1 -W1 -B254 -S0 /dev/sd*[!0-9]

## Improve NVME
if "$(find /sys/block/nvme[0-9]* | grep -q nvme)"; then
  echo -e "options nvme_core default_ps_max_latency_us=0" | sudo tee /etc/modprobe.d/nvme.conf
fi

## Improve PCI latency
sudo setpci -v -s '*:*' latency_timer=10 >/dev/null 2>&1
sudo setpci -v -s '0:0' latency_timer=0 >/dev/null 2>&1

## Improve preload
sudo sed -i -e 's/sortstrategy =.*/sortstrategy = 0/' /etc/preload.conf

echo -e "Disable fsck"
sudo tune2fs -c 0 -i 0 "$(df / | grep / | awk '{print $1}')"
sudo tune2fs -c 0 -i 0 "$(df /home | grep /home | awk '{print $1}')"
echo -e "Disable checksum"
sudo tune2fs -O ^metadata_csum "$(df / | grep / | awk '{print $1}')"
sudo tune2fs -O ^metadata_csum "$(df /home | grep /home | awk '{print $1}')"
echo -e "Disable quota"
sudo tune2fs -O ^quota "$(df / | grep / | awk '{print $1}')"
sudo tune2fs -O ^quota "$(df /home | grep /home | awk '{print $1}')"

echo -e "Disable logging services"
sudo systemctl mask dev-mqueue.mount >/dev/null 2>&1
sudo systemctl mask sys-kernel-tracing.mount >/dev/null 2>&1
sudo systemctl mask sys-kernel-debug.mount >/dev/null 2>&1
sudo systemctl mask sys-kernel-config.mount >/dev/null 2>&1
sudo systemctl mask systemd-update-utmp.service >/dev/null 2>&1
sudo systemctl mask systemd-update-utmp-runlevel.service >/dev/null 2>&1
sudo systemctl mask systemd-update-utmp-shutdown.service >/dev/null 2>&1
sudo systemctl mask systemd-journal-flush.service >/dev/null 2>&1
sudo systemctl mask systemd-journal-catalog-update.service >/dev/null 2>&1
sudo systemctl mask systemd-journald-dev-log.socket >/dev/null 2>&1
sudo systemctl mask systemd-journald-audit.socket >/dev/null 2>&1
sudo systemctl mask logrotate.service >/dev/null 2>&1
sudo systemctl mask logrotate.timer >/dev/null 2>&1
sudo systemctl mask syslog.service >/dev/null 2>&1
sudo systemctl mask syslog.socket >/dev/null 2>&1
sudo systemctl mask rsyslog.service >/dev/null 2>&1

echo -e "Disable GPU polling"
echo -e "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf

sudo update-initramfs -u -k all

# Don't reserve space man-pages, locales, licenses.
echo -e "Remove useless companies"
find /usr/share/doc/ -depth -type f ! -name copyright -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.gz' -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.pdf' -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.tex' -exec sudo rm -f {} + || :
find /usr/share/doc/ -depth -type d -empty -exec sudo rmdir {} + || :
sudo rm -rfd /usr/share/groff/* /usr/share/info/* /usr/share/lintian/* \
  /usr/share/linda/* /var/cache/man/* /usr/share/man/* /usr/share/X11/locale/!\(en_US\)
sudo rm -rfd /usr/share/locale/!\(en_US\)

echo -e "Flush flatpak database"
sudo flatpak uninstall --unused --delete-data -y
sudo flatpak repair
echo -e "Clear the caches"
# Optimize: Use single find command instead of loop
find / -type d \( -name ".tmp" -o -name ".temp" -o -name ".cache" \) -exec sudo find {} -type f -delete \; 2>/dev/null || :
echo -e "Clear the patches"
rm -rfd /{tmp,var/tmp}/{.*,*}
sudo pacman -Qtdq \
  && sudo pacman -Runs --noconfirm "$(/bin/pacman -Qttdq)"
sudo pacman -Sc --noconfirm
sudo pacman -Scc -y
sudo pacman-key --refresh-keys
sudo pacman-key --populate archlinux
yay -Yc --noconfirm
sudo paccache -rk 0
sudo pacman-optimize
sudo pacman -Dk

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
echo -e "Scrub free space and sync"
echo -e "kernel.core_pattern=/dev/null" | sudo tee /etc/sysctl.d/50-coredump.conf
sudo dd bs=4k if=/dev/null of=/var/tmp/dummy || sudo rm -rfd /var/tmp/dummy
sync -f

sudo netselect-apt stable && sudo mv sources.list /etc/apt/sources.list && sudo apt update

sudo sh -c 'echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io'

# apt-fast
#sudo micro /etc/apt/sources.list.d/apt-fast.list
sudo touch /etc/apt/sources.list.d/apt-fast.list \
  && echo "deb [signed-by=/etc/apt/keyrings/apt-fast.gpg] http://ppa.launchpad.net/apt-fast/stable/ubuntu focal main" | sudo tee -a /etc/apt/sources.list.d/apt-fast.list

mkdir -p /etc/apt/keyrings
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBC5934FD3DEBD4DAEA544F791E2824A7F22B44BD" | sudo gpg --dearmor -o /etc/apt/keyrings/apt-fast.gpg
sudo apt-get update && sudo apt-get install apt-fast

# Deb-get
sudo apt install curl lsb-release wget
curl -sL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | sudo -E bash -s install deb-get

# Eget
curl -s https://zyedidia.github.io/eget.sh | sh
cp -v eget "$HOME"/.local/bin/eget

# Pacstall
sudo apt install pacstall
sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install || wget -q https://pacstall.dev/q/install -O -)"

sudo apt install flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Zoxide
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
# Navi
curl -sSfL https://raw.githubusercontent.com/denisidoro/navi/master/scripts/install | bash

# Ripgrep-all
# https://github.com/phiresky/ripgrep-all

sudo apt-get install -y fd-find && ln -sf "$(command -v fdfind)" "~/.local/bin/fd"

# Eza
sudo apt update && apt-get install -y gpg
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
apt-get update
apt-get install -y eza

## Fix timeout for tty
# Apply immediately
sudo sysctl -w kernel.hung_task_timeout_secs=0
echo 0 | sudo tee /proc/sys/kernel/hung_task_timeout_secs

# Make it permanent
echo "kernel.hung_task_timeout_secs = 0" | sudo tee /etc/sysctl.d/99-disable-hung-tasks.conf

# Reload configs so it's applied now (and on boot)
sudo sysctl --system

python3 -m pip install --upgrade pip
pip cache purge
apt-get remove lib*-doc
flatpak uninstall --unused --delete-data
docker system prune --all --volumes
sudo apt remove texlive-*-doc
sudo apt-get --purge remove tex.\*-doc$

sudo apt install --fix-missings
sudo apt install --fix-broken
pip install --upgrade pip

# YT-DLP
sudo add-apt-repository ppa:tomtomtom/yt-dlp # Add ppa repo to apt
sudo apt update                              # Update package list
apt-get install yt-dlp                       # Install yt-dlp

# DISABLE THESE SERVICES ON OLD SYSTEMS
sudo apt remove whoopsie               # Error Repoting
sudo systemctl mask packagekit.service # gnome-software
sudo systemctl mask geoclue.service    # CAUTION: Disable if you don't use Night Light or location services
apt-get remove gnome-online-accounts   # Gnome online accounts plugins

sudo apt-get install rustup

APPS=(
  btrfs-progs
  fzf
  nala
  bat
  rust-sd
  ripgrep
  fd-find
  ugrep
  gpg
)
sudo apt install "$APPS"
