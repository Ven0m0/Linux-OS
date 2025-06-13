#!/bin/bash

# Download and install BleachBit custom cleaners
REPO_URL="https://github.com/Ven0m0/Linux-OS.git"
DEST="$HOME/.config/bleachbit"

git clone --depth 1 "$REPO_URL" bleachbitc \
  && mkdir -p "$DEST" \
  && { cpz -r bleachbitc/Cachyos/cleaners "$DEST/" 2>/dev/null || cp -r bleachbitc/Cachyos/cleaners "$DEST/"; } \
  && { rmz -rf bleachbitc 2>/dev/null || rm -rf bleachbitc; }

echo "✅ Cleaners installed to $DEST/cleaners"
