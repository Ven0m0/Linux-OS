#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar

# Install QEMU, Virt-Manager, and TPM emulator
sudo pacman -S --needed --noconfirm qemu-desktop virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat swtpm edk2-ovmf
# Install VirtIO drivers (AUR) - Essential for near-native performance
paru -S --needed --noconfirm --skipreview virtio-win
# Enable libvirt daemon
sudo systemctl enable --now libvirtd

# Add yourself to libvirt group (re-login required after this)
sudo usermod -aG libvirt "$USER"

echo "add 'intel_iommu=on' to your kernel cmdline!"
echo "Debloat windows: iwr -useb christitus.com/win | iex"
