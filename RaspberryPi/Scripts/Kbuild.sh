#!/bin/bash
#
# Build and install a custom Raspberry Pi kernel.
#

set -euo pipefail

# Ensure we're running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

# Install dependencies
apt-get update && apt-get install -y --no-install-recommends \
  bc \
  bison \
  build-essential \
  ca-certificates \
  cpio \
  flex \
  git \
  kmod \
  libncurses-dev \
  libssl-dev \
  rsync

# Clone the repository
git clone --depth=1 --branch rpi-6.16.y https://github.com/raspberrypi/linux /usr/src/linux

# Configure the build
cd /usr/src/linux
make bcm2711_defconfig

# Build the kernel and modules
make -j"$(nproc)" Image.gz modules dtbs

# Install the modules
make modules_install

# Install the kernel
cp arch/arm64/boot/dts/broadcom/*.dtb /boot/
cp arch/arm64/boot/dts/overlays/*.dtb* /boot/overlays/
cp arch/arm64/boot/dts/overlays/README /boot/overlays/
cp arch/arm64/boot/Image.gz /boot/kernel8.img

# Update the bootloader
echo "dtoverlay=vc4-kms-v3d" >>/boot/config.txt

# Reboot
echo "Rebooting in 10 seconds..."
sleep 10
reboot
