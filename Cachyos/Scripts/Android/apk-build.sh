#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

apk="$1"
tmp="workdir"
out="optimized.apk"

rm -rf "$tmp"
unzip "$apk" -d "$tmp" &>/dev/null

# strip unused densities
for d in drawable-xxhdpi drawable-xxxhdpi; do
  rm -rf "$tmp/res/$d"
done
rm -rf app_decoded/res/drawable-xxhdpi/
rm -rf app_decoded/res/values-fr/

# recompress images
find "$tmp/res" -type f -name '*.png' -print0 | xargs -0 zopflipng -m

zstd -19 assets/large.png -o compressed
d8 --release --output optimized.dex classes.dex

apktool b "$tmp" -o new.apk
# zipalign
zipalign -fpv 4 "$tmp" "$out"
# sign
apksigner sign --ks mykeystore "$out"
