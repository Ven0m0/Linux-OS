#!/usr/bin/env bash
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/cleaning.sh"

# Setup environment
setup_environment

# Install packages without user interaction
export DEBIAN_FRONTEND=noninteractive

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
