#!/usr/bin/env bash

# install packages without user interaction:
export DEBIAN_FRONTEND=noninteractive

echo "### Reducing the size of the installation ###"

DISK_USAGE_BEFORE=$(df -h)
echo "==> Disk usage before cleanup $DISK_USAGE_BEFORE"

echo "==> Removing documentation and manuals"
docman='path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
# lintian stuff is small, but really unnecessary
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*'
printf '%s\n' "$docman" | sudo tee /etc/dpkg/dpkg.cfg.d/01_nodoc
unset docman

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
apt-get -y clean
apt-get -y autoclean
apt-get -y autoremove --purge
#echo "==> Removing APT lists"
find /var/lib/apt/lists -type f -delete
echo "==> Removing man pages"
find /usr/share/man -type f -delete
#echo "==> Removing anything in /usr/src"
#rm -rf /usr/src/*
echo "==> Removing any docs"
find /usr/share/doc -type f -delete
echo "==> Removing caches"
find /var/cache -type f -delete
echo "==> Removing groff info lintian linda"
rm -rf /usr/share/groff/* /usr/share/info/* /usr/share/lintian/* /usr/share/linda/*

### https://github.com/boxcutter/debian/blob/main/script/cleanup.sh

# Remove Bash history
unset HISTFILE
rm -f /root/.bash_history
rm -f "$HOME"/.bash_history

# Clean up log files
find /var/log -type f | while read f; do echo -ne '' >"$f"; done

echo "==> Disk usage before cleanup"
echo "$DISK_USAGE_BEFORE_CLEANUP"

echo "==> Disk usage after cleanup"
df -h
