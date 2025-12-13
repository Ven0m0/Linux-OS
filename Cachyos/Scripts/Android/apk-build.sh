#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C
apk="$1"
tmp="workdir"
out="optimized.apk"

rm -rf "$tmp"
unzip "$apk" -d "$tmp" &>/dev/null
# (resources minification)
for d in drawable-xxhdpi drawable-xxxhdpi values-fr; do
  rm -rf "$tmp/res/$d"
done
for rem in "$tmp"/res/{drawable-*,values-*}; do
  [[ "$rem" =~ -en|-zh ]] && rm -rf "$rem"
done
# recompress PNGs
find "$tmp/res" -type f -name '*.png' -print0 | xargs -0 zopflipng -m || :
# (optional) recompress other large assets with zstd
find "$tmp/assets" -type f -print0 | xargs -0 -I{} sh -c 'zstd -19 "{}" -o "{}.zst" && mv "{}.zst" "{}"' || :
# rebuild & align
apktool b "$tmp" -o new.apk
zipalign -f -p 4 new.apk "$out"
# sign
apksigner sign --ks mykeystore "$out"
