#!/bin/bash

# https://github.com/0xf0xx0/dotfiles/blob/dots/eggs/bin/buildkernel.sh

set -eu
MAKEFLAGS=-j$(nproc)
export MAKEFLAGS
export INSTALL_PATH=/boot/linux

mkdir -p kernel
cd kernel

echo "Grabbing kernel and patches..."
rm -r patches 2>/dev/null || : # just in case
git clone --depth=1 https://github.com/t2linux/linux-t2-patches patches
pkgver=$(curl -sL https://github.com/t2linux/T2-Ubuntu-Kernel/releases/latest/ | grep "<title>Release" | awk -F " " '{print $2}' | cut -d "v" -f 2 | cut -d "-" -f 1)
_srcname=linux-${pkgver}
wget https://kernel.org/pub/linux/kernel/v"${pkgver//.*/}".x/"$_srcname".tar.xz
tar xvf "$_srcname".tar.xz
cd "$_srcname"

#git clone --depth=1 https://github.com/kekrby/apple-bce drivers/staging/apple-bce
# ^ out of date, applied in patch 1001
echo "Applying patches..."
for patch in ../patches/*.patch; do
  patch -Np1 <"$patch"
done

zcat /proc/config.gz >.config
kernelver=$(make kernelversion)
localver=$(grep 'CONFIG_LOCALVERSION=' .config | awk -F '"' '{print $2}')
kernelmajminver=$(echo "$kernelver" | awk -F "." '{print $1 "." $2}')

# grab RT patchset
rtpatchfile=$(curl -s --location "https://kernel.org/pub/linux/kernel/projects/rt/$kernelmajminver/" | grep -ioE '<a href="(patch-.+)">' | awk -F '"' '{print $2}' | tail -n 1)
rtver=$(echo "$rtpatchfile" | awk -F "-" '{print $3}' | awk -F "\\\." '{print "-" $1}')

if [[ -n $rtpatchfile ]]; then
  echo "Grabbing real-time patches..."
  wget -O "../patches/$rtpatchfile" "https://kernel.org/pub/linux/kernel/projects/rt/$kernelmajminver/$rtpatchfile" || :
  xz -d "../patches/$rtpatchfile" || :

  echo "Applying real-time patches..."
  patch -Np1 <"../patches/$(echo "$rtpatchfile" | head -c -4)" || :
else
  echo "Real-time patches not grabbed."
fi

echo "Making configs..."
# Disable debug info
./scripts/config --undefine GDB_SCRIPTS
./scripts/config --undefine DEBUG_INFO
./scripts/config --undefine DEBUG_INFO_SPLIT
./scripts/config --undefine DEBUG_INFO_REDUCED
./scripts/config --undefine DEBUG_INFO_COMPRESSED
./scripts/config --set-val DEBUG_INFO_NONE y
./scripts/config --set-val DEBUG_INFO_DWARF5 n
make olddefconfig
scripts/config --module CONFIG_BT_HCIBCM4377
scripts/config --module CONFIG_HID_APPLE_IBRIDGE
scripts/config --module CONFIG_HID_APPLE_TOUCHBAR
scripts/config --module CONFIG_HID_APPLE_MAGIC_BACKLIGHT

echo "Building kernel..."
make
make modules_install

echo "Installing..."
kernel-install add "$kernelver$rtver$localver" ./vmlinux
