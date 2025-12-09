#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -Eeuo pipefail
shopt -s nullglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# optimize_apk.sh: Automate APK linting, stripping, bytecode optimization, and repackaging
# Usage: ./optimize_apk.sh input.apk output.apk
# Requirements: apktool, redex, dex2jar, proguard (or R8), zipalign, apksigner, pngcrush, jpegoptim, 7z

# Configuration (adjust via env vars or use defaults)
KEYSTORE_PATH="${KEYSTORE_PATH:-mykey.keystore}"
KEY_ALIAS="${KEY_ALIAS:-myalias}"
KEYSTORE_PASS="${KEYSTORE_PASS:-changeit}"
KEY_PASS="${KEY_PASS:-changeit}"

# Tools
readonly APKTOOL="apktool"
readonly REDEX="redex"
readonly DEX2JAR="d2j-dex2jar.sh"
readonly PROGUARD_JAR="${PROGUARD_JAR:-proguard.jar}"
readonly ZIPALIGN="zipalign"
readonly APKSIGNER="apksigner"
readonly PNGCRUSH="pngcrush"
readonly JPEGOPTIM="jpegoptim"
readonly SEVENZIP="7z"

# Logging
log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
err(){ printf '[ERROR] %s\n' "$*" >&2; }
die(){
  err "$1"
  exit "${2:-1}"
}

# Check required tools
has(){ command -v "$1" &>/dev/null; }

check_tools(){
  local missing=0
  for tool in "$APKTOOL" "$ZIPALIGN" "$APKSIGNER" "$SEVENZIP"; do
    if ! has "$tool"; then
      err "Required tool not found: $tool"
      missing=1
    fi
  done
  [[ $missing -eq 1 ]] && die "Missing required tools"
}

# Input/Output validation
INPUT_APK="${1:-}"
OUTPUT_APK="${2:-}"

if [[ -z $INPUT_APK || -z $OUTPUT_APK ]]; then
  die "Usage: $0 input.apk output.apk"
fi

[[ -f $INPUT_APK ]] || die "Input APK not found: $INPUT_APK"

# Working Directory with cleanup
WORKDIR="$(mktemp -d)"
cleanup(){
  [[ -n ${WORKDIR:-} && -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR" || :
}
trap cleanup EXIT
trap 'err "failed at line ${LINENO}"' ERR

# Validate tools
check_tools

log "[1/10] Decoding APK with apktool..."
"$APKTOOL" d "$INPUT_APK" -o "$WORKDIR/src" || die "Failed to decode APK"

log "[2/10] Stripping unused resources..."
# Remove extra densities (keep only mdpi)
find "$WORKDIR/src/res" -maxdepth 1 -type d -name "drawable-*" ! -name "drawable-mdpi" -exec rm -rf {} + 2>/dev/null || :
# Remove raw resources and assets if present
rm -rf "$WORKDIR/src/res/raw/" "$WORKDIR/src/assets/" 2>/dev/null || :

log "[3/10] Rebuilding stripped APK..."
"$APKTOOL" b "$WORKDIR/src" -o "$WORKDIR/stripped.apk" || die "Failed to rebuild APK"

log "[4/10] Running Redex optimization..."
if has "$REDEX"; then
  "$REDEX" -i "$WORKDIR/stripped.apk" -o "$WORKDIR/redexed.apk" || {
    log "Redex optimization failed, using stripped APK"
    cp "$WORKDIR/stripped.apk" "$WORKDIR/redexed.apk"
  }
else
  log "Redex not found, skipping bytecode optimization"
  cp "$WORKDIR/stripped.apk" "$WORKDIR/redexed.apk"
fi

log "[5/10] Converting DEX to JAR for ProGuard/R8..."
if has "$DEX2JAR" && [[ -f $PROGUARD_JAR ]]; then
  "$DEX2JAR" "$WORKDIR/redexed.apk" -o "$WORKDIR/app.jar" || {
    log "DEX to JAR conversion failed, skipping ProGuard"
    cp "$WORKDIR/redexed.apk" "$WORKDIR/repackaged.apk"
  }

  log "[6/10] Running ProGuard shrink..."
  cat >"$WORKDIR/proguard-rules.pro" <<EOL
-keep public class * {
    public *;
}
-dontwarn **
-dontobfuscate
-printmapping mapping.txt
EOL

  java -jar "$PROGUARD_JAR" \
    -injars "$WORKDIR/app.jar" \
    -outjars "$WORKDIR/app_proguard.jar" \
    -libraryjars "${JAVA_HOME}/lib/rt.jar" \
    -include "$WORKDIR/proguard-rules.pro"

  log "[7/10] Rebuilding DEX from optimized JAR..."
  if has dx; then
    dx --dex --output="$WORKDIR/classes.dex" "$WORKDIR/app_proguard.jar"
    # Repackage
    unzip -q "$WORKDIR/redexed.apk" -d "$WORKDIR/apk_unpack"
    cp "$WORKDIR/classes.dex" "$WORKDIR/apk_unpack/"
    cd "$WORKDIR/apk_unpack" || exit
    zip -q -r ../repackaged.apk .
    cd - >/dev/null || die "Failed to return from working directory"
  else
    log "dx not found, skipping ProGuard integration"
    cp "$WORKDIR/redexed.apk" "$WORKDIR/repackaged.apk"
  fi
else
  log "dex2jar or proguard.jar not found, skipping ProGuard"
  cp "$WORKDIR/redexed.apk" "$WORKDIR/repackaged.apk"
fi

log "[8/10] Aligning APK..."
"$ZIPALIGN" -v -p 4 "$WORKDIR/repackaged.apk" "$WORKDIR/aligned.apk" >/dev/null || die "Failed to align APK"

log "[9/10] Signing APK..."
if [[ -f $KEYSTORE_PATH ]]; then
  "$APKSIGNER" sign \
    --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" \
    --ks-pass pass:"$KEYSTORE_PASS" --key-pass pass:"$KEY_PASS" \
    --out "$WORKDIR/signed.apk" \
    "$WORKDIR/aligned.apk" || die "Failed to sign APK"
else
  log "Keystore not found at $KEYSTORE_PATH. Skipping signing (APK will be unsigned)"
  cp "$WORKDIR/aligned.apk" "$WORKDIR/signed.apk"
fi

log "[10/10] Optimizing PNGs and JPEGs..."
# Unzip to optimize resources
unzip -q "$WORKDIR/signed.apk" -d "$WORKDIR/final_unpack" || die "Failed to unzip signed APK"
if has "$PNGCRUSH"; then
  find "$WORKDIR/final_unpack/res" -iname "*.png" -exec "$PNGCRUSH" -q -rem alla -brute {} {}.opt \; -exec mv {}.opt {} + 2>/dev/null || :
fi
if has "$JPEGOPTIM"; then
  find "$WORKDIR/final_unpack/res" -iname "*.jpg" -exec "$JPEGOPTIM" --strip-all {} + 2>/dev/null || :
fi

# Rezip final APK
cd "$WORKDIR/final_unpack" || die "Failed to enter final unpack directory"
"$SEVENZIP" a -tzip -mx=9 "../output.apk" . >/dev/null || die "Failed to create final APK"
cd - >/dev/null || die "Failed to return from working directory"

mv "$WORKDIR/output.apk" "$OUTPUT_APK" || die "Failed to move output APK"
log "✅ Optimized APK created at: $OUTPUT_APK"
