#!/usr/bin/env bash

PATCH_PATH="$HOME/.config/neofetch/neowofetch.patch"
URL="https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Linux-Settings/Home/.config/neofetch/neowofetch.patch"

if [[ ! -f "$PATCH_PATH" ]]; then
  mkdir -p "${PATCH_PATH%/*}"
  curl -fsSL "$URL" -o "$PATCH_PATH" || { echo "Failed to download patch"; exit 1; }
fi
sudo patch "$(command -v neofetch)" < "$PATCH_PATH"
