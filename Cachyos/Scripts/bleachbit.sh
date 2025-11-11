#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || exit 1

# Download and install BleachBit custom cleaners
REPO_URL="https://github.com/Ven0m0/Linux-OS.git"
DEST="$HOME/.config/bleachbit"

git clone --depth 1 "$REPO_URL" bleachbitc \
  && mkdir -p "$DEST" \
  && { cpz -r bleachbitc/Cachyos/cleaners "$DEST/" 2>/dev/null || cp -r bleachbitc/Cachyos/cleaners "$DEST/"; } \
  && { rmz -rf bleachbitc 2>/dev/null || rm -rf bleachbitc; }

log "${GRN}✅ Cleaners installed to $DEST/cleaners${DEF}"
