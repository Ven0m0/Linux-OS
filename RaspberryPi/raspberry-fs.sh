#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

sudo -v

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
FILE="$SCRIPT_DIR/DietPi_RPi234-ARMv8-Bookworm.img"

if [[ -f "$FILE" ]]; then
    echo "Found file: $FILE"
    echo chmod +x raspberry_f2fs.sh
    sudo $SCRIPT_DIR/raspberry_f2fs.sh "$FILE" /dev/sdb
else
    echo "File not found!"
fi

