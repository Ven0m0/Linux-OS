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

# Clean APT package manager cache
clean_apt_cache() {
  sudo apt-get clean -yq
  sudo apt-get autoclean -yq
  sudo apt-get autoremove --purge -yq
}

# Clean system cache directories
clean_cache_dirs() {
  sudo rm -rf /tmp/* 2>/dev/null || :
  sudo rm -rf /var/tmp/* 2>/dev/null || :
  sudo rm -rf /var/cache/apt/archives/* 2>/dev/null || :
  rm -rf ~/.cache/* 2>/dev/null || :
  sudo rm -rf /root/.cache/* 2>/dev/null || :
  rm -rf ~/.thumbnails/* 2>/dev/null || :
  rm -rf ~/.cache/thumbnails/* 2>/dev/null || :
}

# Clean shell and Python history files
clean_history_files() {
  rm -f ~/.python_history 2>/dev/null || :
  sudo rm -f /root/.python_history 2>/dev/null || :
  rm -f ~/.bash_history 2>/dev/null || :
  sudo rm -f /root/.bash_history 2>/dev/null || :
  history -c 2>/dev/null || :
}

echo "### Reducing the size of the installation ###"

DISK_USAGE_BEFORE=$(df -h)
echo "==> Disk usage before cleanup $DISK_USAGE_BEFORE"

echo "==> Removing documentation and manuals"
configure_dpkg_nodoc

echo "==> install localepurge to remove all unnecesary languages"
apt-get install -y localepurge
localepurge

# source: https://github.com/box-cutter/debian-vm/blob/master/script/minimize.sh
echo "==> Installed packages before cleanup"
dpkg --get-selections | grep -v deinstall | cut -f 1 | xargs

# Remove some packages to get a minimal install
echo "==> Removing all linux kernels except the currrent one"
dpkg --list | awk '{ print $2 }' | grep 'linux-image-3.*-generic' | grep -v "$(uname -r)" | xargs apt-get -y purge

#echo "==> Removing linux headers"
#dpkg --list | awk '{ print $2 }' | grep linux-headers | xargs apt-get -y purge
#rm -rf /usr/src/linux-headers*
#echo "==> Removing linux source"
#dpkg --list | awk '{ print $2 }' | grep linux-source | xargs apt-get -y purge
#echo "==> Removing development packages"
#dpkg --list | awk '{ print $2 }' | grep -- '-dev$' | xargs apt-get -y purge

echo "==> Removing documentation packages"
dpkg --list | awk '{ print $2 }' | grep -- '-doc$' | xargs apt-get -y purge

echo "==> Removing X11 libraries"
apt-get -y purge libx11-data xauth libxmuu1 libxcb1 libx11-6 libxext6

echo "==> Removing other oddities"
apt-get -y purge popularity-contest installation-report wireless-tools wpasupplicant

#optional
#echo "==> Removing default system Python"
#apt-get -y purge python-dbus libnl1 python-smartpm python-twisted-core libiw30 python-twisted-bin libdbus-glib-1-2 python-pexpect python-pycurl python-serial python-gobject python-pam python-openssl

# Clean up orphaned packages with deborphan
apt-get -y install deborphan

echo "==> Purge prior removed packages"
dpkg -l | grep "^rc" | cut -f 3 -d" " | xargs apt-get -y purge

# Clean up the apt cache
clean_apt_cache
#echo "==> Removing APT lists"
find /var/lib/apt/lists -type f -delete 2>/dev/null || :
echo "==> Removing documentation"
clean_documentation
echo "==> Removing caches"
clean_cache_dirs

### https://github.com/boxcutter/debian/blob/main/script/cleanup.sh

# Remove Bash history
unset HISTFILE
clean_history_files

# Clean up log files
find /var/log -type f | while read f; do echo -ne '' >"$f"; done

echo "==> Disk usage before cleanup"
echo "$DISK_USAGE_BEFORE_CLEANUP"

echo "==> Disk usage after cleanup"
df -h
