#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C
# optimize_apk.sh: Automate APK linting, stripping, bytecode optimization, and repackaging
# Usage: ./optimize_apk.sh input.apk output.apk
# Requirements: apktool, redex, dex2jar, proguard (or R8), zipalign, apksigner, pngcrush, jpegoptim, 7z
# Configuration: adjust paths and keystore info via env vars or defaults
KEYSTORE_PATH="${KEYSTORE_PATH:-mykey.keystore}"
KEY_ALIAS="${KEY_ALIAS:-myalias}"
KEYSTORE_PASS="${KEYSTORE_PASS:-changeit}"
KEY_PASS="${KEY_PASS:-changeit}"
# Tools
APKTOOL="apktool"
REDEX="redex"
DEX2JAR="d2j-dex2jar.sh"
PROGUARD_JAR="proguard.jar"
ZIPALIGN="zipalign"
APKSIGNER="apksigner"
PNGCRUSH="pngcrush"
JPEGOPTIM="jpegoptim"
SEVENZIP="7z"
# Check tools
for tool in "$APKTOOL" "$ZIPALIGN" "$APKSIGNER" "$SEVENZIP"; do
  command -v "$tool" &>/dev/null || {
    echo "Error: $tool not found"; exit 1
  }
done

# Input/Output
INPUT_APK="${1:-}"
OUTPUT_APK="${2:-}"

if [[ -z $INPUT_APK || -z $OUTPUT_APK ]]; then
  echo "Usage: $0 input.apk output.apk"; exit 1
fi

# Working Directory
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "[1/10] Decoding APK with apktool..."
"$APKTOOL" d "$INPUT_APK" -o "$WORKDIR/src"

echo "[2/10] Stripping unused resources..."
# Example: remove extra densities
find "$WORKDIR/src/res" -maxdepth 1 -type d -name "drawable-*" ! -name "drawable-mdpi" -exec rm -rf {} + 2>/dev/null || :
# Remove other unused
rm -rf "$WORKDIR/src/res/raw/" "$WORKDIR/src/assets/" 2>/dev/null || :

echo "[3/10] Rebuilding stripped APK..."
"$APKTOOL" b "$WORKDIR/src" -o "$WORKDIR/stripped.apk"

echo "[4/10] Running Redex optimization..."
if command -v "$REDEX" &>/dev/null; then
  "$REDEX" -i "$WORKDIR/stripped.apk" -o "$WORKDIR/redexed.apk"
else
  echo "Redex not found, skipping..."
  cp "$WORKDIR/stripped.apk" "$WORKDIR/redexed.apk"
fi

echo "[5/10] Converting DEX to JAR for ProGuard/R8..."
if command -v "$DEX2JAR" &>/dev/null && [[ -f $PROGUARD_JAR ]]; then
  "$DEX2JAR" "$WORKDIR/redexed.apk" -o "$WORKDIR/app.jar"

  echo "[6/10] Running ProGuard shrink..."
  cat > "$WORKDIR/proguard-rules.pro" << EOL
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

  echo "[7/10] Rebuilding DEX from optimized JAR..."
  if command -v dx &>/dev/null; then
    dx --dex --output="$WORKDIR/classes.dex" "$WORKDIR/app_proguard.jar"
    # Repackage
    unzip -q "$WORKDIR/redexed.apk" -d "$WORKDIR/apk_unpack"
    cp "$WORKDIR/classes.dex" "$WORKDIR/apk_unpack/"
    cd "$WORKDIR/apk_unpack" || exit
    zip -q -r ../repackaged.apk .
    cd - >/dev/null || exit
  else
    echo "dx not found, skipping ProGuard integration..."
    cp "$WORKDIR/redexed.apk" "$WORKDIR/repackaged.apk"
  fi
else
  echo "dex2jar or proguard.jar not found, skipping ProGuard..."
  cp "$WORKDIR/redexed.apk" "$WORKDIR/repackaged.apk"
fi

echo "[8/10] Aligning APK..."
"$ZIPALIGN" -v -p 4 "$WORKDIR/repackaged.apk" "$WORKDIR/aligned.apk" >/dev/null

echo "[9/10] Signing APK..."
if [[ -f $KEYSTORE_PATH ]]; then
  "$APKSIGNER" sign \
    --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" \
    --ks-pass pass:"$KEYSTORE_PASS" --key-pass pass:"$KEY_PASS" \
    --out "$WORKDIR/signed.apk" \
    "$WORKDIR/aligned.apk"
else
  echo "Keystore not found at $KEYSTORE_PATH. Skipping signing (APK will be unsigned)."
  cp "$WORKDIR/aligned.apk" "$WORKDIR/signed.apk"
fi

echo "[10/10] Optimizing PNGs and JPEGs..."
# Unzip to optimize resources
unzip -q "$WORKDIR/signed.apk" -d "$WORKDIR/final_unpack"
if command -v "$PNGCRUSH" &>/dev/null; then
  find "$WORKDIR/final_unpack/res" -iname "*.png" -exec "$PNGCRUSH" -q -rem alla -brute {} {}.opt \; -exec mv {}.opt {} +
fi
if command -v "$JPEGOPTIM" &>/dev/null; then
  find "$WORKDIR/final_unpack/res" -iname "*.jpg" -exec "$JPEGOPTIM" --strip-all {} +
fi

# Rezip final APK
cd "$WORKDIR/final_unpack" || exit
"$SEVENZIP" a -tzip -mx=9 "../output.apk" . >/dev/null
cd - >/dev/null || exit

mv "$WORKDIR/output.apk" "$OUTPUT_APK"
echo "✅ Optimized APK created at: $OUTPUT_APK"
