#!/bin/bash

# Download and install BleachBit custom cleaners
REPO_URL="https://github.com/Ven0m0/Linux-OS.git"
DEST="$HOME/.config/bleachbit"

git clone --depth 1 "$REPO_URL" bleachbitc \
  && mkdir -p "$DEST" \
  && cp -r bleachbitc/Cachyos/cleaners "$DEST/" \
  && rm -rf bleachbitc

echo "✅ Cleaners installed to $DEST/cleaners"
