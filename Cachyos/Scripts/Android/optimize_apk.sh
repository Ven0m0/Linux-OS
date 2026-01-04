#!/usr/bin/env bash
# optimize_apk.sh - Advanced APK Optimizer (Resources, Align, Sign)
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# --- Config ---
KEYSTORE_PATH="${KEYSTORE_PATH:-mykey.keystore}"
KEY_ALIAS="${KEY_ALIAS:-myalias}"
KEYSTORE_PASS="${KEYSTORE_PASS:-changeit}"
KEY_PASS="${KEY_PASS:-changeit}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# --- Helpers ---
R=$'\e[31m' G=$'\e[32m' B=$'\e[34m' X=$'\e[0m'
log() { printf "%b[%s]%b %s\n" "$B" "$(date +%T)" "$X" "$*"; }
die() {
  printf "%b[ERR]%b %s\n" "$R" "$X" "$*" >&2
  exit 1
}
has() { command -v "$1" >/dev/null; }
req() { has "$1" || die "Missing dependency: $1"; }

# --- Logic ---
optimize_images() {
  local dir="$1"
  log "Optimizing assets (Parallel)..."

  # PNG Optimization
  if has zopflipng; then
    find "$dir" -type f -name "*.png" -print0 | xargs -0 -P$(nproc) -I{} zopflipng -y -m --lossless --filters=01234mepb "{}" "{}" >/dev/null 2>&1
  elif has pngcrush; then
    find "$dir" -type f -name "*.png" -print0 | xargs -0 -P$(nproc) -I{} sh -c 'pngcrush -q -rem alla -brute "$1" "$1.tmp" && mv "$1.tmp" "$1"' _ "{}"
  else
    log "Skipping PNGs (zopflipng/pngcrush not found)"
  fi

  # JPG Optimization
  if has jpegoptim; then
    find "$dir" -type f \( -name "*.jpg" -o -name "*.jpeg" \) -print0 | xargs -0 -P$(nproc) jpegoptim --strip-all --quiet
  fi
}

repack() {
  local src="$1" dst="$2"
  log "Repacking to $dst..."
  pushd "$src" >/dev/null
  # APKs must be standard ZIP (Deflate). 7z provides better compression ratios than 'zip'.
  # -mx9: Ultra compression, -mm=Deflate: Required for Android
  req 7z
  7z a -tzip -mx=9 -mm=Deflate "$dst" . >/dev/null
  popd >/dev/null
}

main() {
  [[ $# -lt 2 ]] && die "Usage: ${0##*/} <input.apk> <output.apk>"
  local input="$1" output="$2"
  [[ -f $input ]] || die "Input not found: $input"

  # 1. Dependency Check
  req unzip
  req zipalign
  req apksigner
  req 7z

  # 2. Extract
  log "Extracting $input..."
  unzip -q "$input" -d "$TMP_DIR/payload"

  # 3. Optimize Resources
  optimize_images "$TMP_DIR/payload/res"

  # 4. Repackage
  local unaligned="$TMP_DIR/unaligned.apk"
  repack "$TMP_DIR/payload" "$unaligned"

  # 5. Align (Must be done before signing for v2+ scheme)
  log "Aligning..."
  local aligned="$TMP_DIR/aligned.apk"
  zipalign -f -p 4 "$unaligned" "$aligned"

  # 6. Sign
  log "Signing..."
  if [[ -f $KEYSTORE_PATH ]]; then
    apksigner sign --ks "$KEYSTORE_PATH" \
      --ks-key-alias "$KEY_ALIAS" \
      --ks-pass "pass:$KEYSTORE_PASS" \
      --key-pass "pass:$KEY_PASS" \
      --out "$output" "$aligned"
    log "Signed successfully: $output"
  else
    log "Keystore ($KEYSTORE_PATH) not found. Copying unsigned aligned APK."
    cp "$aligned" "$output"
    log "Warning: Output is UNALIGNED/UNSIGNED (v2 signature missing)"
  fi
}

main "$@"
