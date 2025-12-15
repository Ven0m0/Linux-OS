#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
# optimize_apk.sh: Decode, strip, shrink, repackage, align, sign, and recompress an APK.
# Usage: ./optimize_apk.sh input.apk output.apk
# Requirements (hard): apktool, zipalign, apksigner, 7z, unzip
# Optional: d2j-dex2jar.sh, proguard.jar, dx, java, zopflipng, pngcrush, jpegoptim, zstd
KEYSTORE_PATH="${KEYSTORE_PATH:-mykey.keystore}"
KEY_ALIAS="${KEY_ALIAS:-myalias}"
KEYSTORE_PASS="${KEYSTORE_PASS:-changeit}"
KEY_PASS="${KEY_PASS:-changeit}"
readonly APKTOOL="apktool"
readonly ZIPALIGN="zipalign"
readonly APKSIGNER="apksigner"
readonly SEVENZIP="7z"
readonly UNZIP="unzip"
readonly DEX2JAR="d2j-dex2jar.sh"
readonly PROGUARD_JAR="${PROGUARD_JAR:-proguard.jar}"
readonly DX="dx"
readonly ZOPFLIPNG="zopflipng"
readonly PNGCRUSH="pngcrush"
readonly JPEGOPTIM="jpegoptim"
readonly ZSTD="zstd"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
err() { printf '[ERROR] %s\n' "$*" >&2; }
die() {
  err "$1"
  exit "${2:-1}"
}
has() { command -v -- "$1" &> /dev/null; }

check_tools() {
  local missing=0
  for tool in "$APKTOOL" "$ZIPALIGN" "$APKSIGNER" "$SEVENZIP" "$UNZIP"; do
    if ! has "$tool"; then
      err "Required tool not found: $tool"
      missing=1
    fi
  done
  [[ $missing -eq 1 ]] && die "Missing required tools"
}
INPUT_APK="${1:-}"
OUTPUT_APK="${2:-}"
[[ -n $INPUT_APK && -n $OUTPUT_APK ]] || die "Usage: $0 input.apk output.apk"
[[ -f $INPUT_APK ]] || die "Input APK not found: $INPUT_APK"
WORKDIR="$(mktemp -d)"
cleanup() { [[ -n ${WORKDIR:-} && -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR"; }
trap cleanup EXIT
trap 'err "failed at line ${LINENO}"' ERR

check_tools
SRC_DIR="$WORKDIR/src"
STRIPPED_APK="$WORKDIR/stripped.apk"
REPACKAGED_APK="$WORKDIR/repackaged.apk"
ALIGNED_APK="$WORKDIR/aligned.apk"
SIGNED_APK="$WORKDIR/signed.apk"
FINAL_DIR="$WORKDIR/final_unpack"
OUTPUT_TMP="$WORKDIR/output.apk"

log "[1/9] Decoding APK with apktool..."
"$APKTOOL" d "$INPUT_APK" -o "$SRC_DIR" > /dev/null

log "[2/9] Stripping resources..."
# Remove heavy density buckets, specific locales, and raw/assets payloads.
for d in drawable-xxhdpi drawable-xxxhdpi values-fr; do
  rm -rf "$SRC_DIR/res/$d"
done
for rem in "$SRC_DIR"/res/{drawable-*,values-*}; do
  [[ -e $rem ]] || continue
  [[ $rem =~ -en|-zh ]] && rm -rf "$rem"
done
find "$SRC_DIR/res" -maxdepth 1 -type d -name "drawable-*" ! -name "drawable-mdpi" -exec rm -rf {} + 2> /dev/null || :
rm -rf "$SRC_DIR/res/raw" "$SRC_DIR/assets" 2> /dev/null || :

log "[3/9] Rebuilding stripped APK..."
"$APKTOOL" b "$SRC_DIR" -o "$STRIPPED_APK" > /dev/null

log "[4/9] Optional ProGuard shrink..."
if has "$DEX2JAR" && [[ -f $PROGUARD_JAR ]] && has java; then
  "$DEX2JAR" "$STRIPPED_APK" -o "$WORKDIR/app.jar" > /dev/null || die "DEX to JAR conversion failed"
  cat > "$WORKDIR/proguard-rules.pro" << 'EOR'
-keep public class * { public *; }
-dontwarn **
-dontobfuscate
-printmapping mapping.txt
EOR
  java -jar "$PROGUARD_JAR" \
    -injars "$WORKDIR/app.jar" \
    -outjars "$WORKDIR/app_proguard.jar" \
    -libraryjars "${JAVA_HOME:-/usr}/lib/rt.jar" \
    -include "$WORKDIR/proguard-rules.pro" > /dev/null
  if has "$DX"; then
    "$DX" --dex --output="$WORKDIR/classes.dex" "$WORKDIR/app_proguard.jar" > /dev/null
    "$UNZIP" -q "$STRIPPED_APK" -d "$WORKDIR/apk_unpack"
    cp "$WORKDIR/classes.dex" "$WORKDIR/apk_unpack/"
    (cd "$WORKDIR/apk_unpack" && zip -q -r "$REPACKAGED_APK" .)
  else
    log "dx not found; skipping ProGuard reintegration"
    cp "$STRIPPED_APK" "$REPACKAGED_APK"
  fi
else
  log "dex2jar/proguard/java missing; skipping shrink"
  cp "$STRIPPED_APK" "$REPACKAGED_APK"
fi

log "[5/9] Aligning APK..."
"$ZIPALIGN" -f -p 4 "$REPACKAGED_APK" "$ALIGNED_APK" > /dev/null

log "[6/9] Signing APK..."
if [[ -f $KEYSTORE_PATH ]]; then
  "$APKSIGNER" sign \
    --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" \
    --ks-pass pass:"$KEYSTORE_PASS" --key-pass pass:"$KEY_PASS" \
    --out "$SIGNED_APK" \
    "$ALIGNED_APK" > /dev/null
else
  log "Keystore not found at $KEYSTORE_PATH; leaving APK unsigned"
  cp "$ALIGNED_APK" "$SIGNED_APK"
fi
log "[7/9] Unpacking for resource recompression..."
"$UNZIP" -q "$SIGNED_APK" -d "$FINAL_DIR"

log "[8/9] Recompressing assets..."
if has "$ZOPFLIPNG"; then
  find "$FINAL_DIR/res" -type f -name '*.png' -print0 | xargs -0 "$ZOPFLIPNG" -m --lossless --iterations=15 --filters=01234mepb &> /dev/null || :
elif has "$PNGCRUSH"; then
  find "$FINAL_DIR/res" -type f -name '*.png' -exec "$PNGCRUSH" -q -rem alla -brute {} {}.opt \; -exec mv {}.opt {} + 2> /dev/null || :
fi
if has "$JPEGOPTIM"; then
  find "$FINAL_DIR/res" -type f \( -name '*.jpg' -o -name '*.jpeg' \) -exec "$JPEGOPTIM" --strip-all {} + 2> /dev/null || :
fi
if has "$ZSTD"; then
  find "$FINAL_DIR/assets" -type f -print0 | xargs -0 -I{} sh -c '[[ -f "{}" ]] || exit 0; zstd -19 "{}" -o "{}.zst" && mv "{}.zst" "{}"' &> /dev/null || :
fi

log "[9/9] Repacking final APK..."
(cd "$FINAL_DIR" && "$SEVENZIP" a -tzip -mx=9 "$OUTPUT_TMP" . > /dev/null)
mv "$OUTPUT_TMP" "$OUTPUT_APK"
log "✅ Optimized APK created at: $OUTPUT_APK"
