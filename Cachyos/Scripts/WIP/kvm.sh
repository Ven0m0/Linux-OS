#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar

sudo pacman -S --needed --noconfirm qemu-desktop virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat swtpm

paru -S --needed --noconfirm --skipreview virtio-win
