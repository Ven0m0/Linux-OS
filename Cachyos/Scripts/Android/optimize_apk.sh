#!/usr/bin/env bash
export LC_ALL=C LANG=C
# optimize_apk.sh: Automate APK linting, stripping, bytecode optimization, and repackaging
# Usage: ./optimize_apk.sh input.apk output.apk
# Requirements: apktool, redex, dex2jar, proguard (or R8), zipalign, apksigner, pngcrush, jpegoptim, 7z

# Configuration: adjust paths and keystore info
KEYSTORE_PATH="mykey.keystore"
KEY_ALIAS="myalias"
KEYSTORE_PASS="changeit"
KEY_PASS="changeit"

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

# Input/Output
INPUT_APK="${1:-0}"
OUTPUT_APK="${2:-0}"
WORKDIR="work_$(printf '%(%s)T' -1)"
# Clean and create working directory
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"

echo "[1/10] Decoding APK with apktool..."
"$APKTOOL" d "$INPUT_APK" -o "$WORKDIR/src"

echo "[2/10] Stripping unused resources..."
# Example: remove extra densities
find -O3 "$WORKDIR/src/res" -maxdepth 1 -type d -name "drawable-*" ! -name "drawable-mdpi" -exec rm -rf {} +
# Remove other unused
rm -rf "$WORKDIR/src/res/raw/" "$WORKDIR/src/assets/"

echo "[3/10] Rebuilding stripped APK..."
"$APKTOOL" b "$WORKDIR/src" -o "$WORKDIR/stripped.apk"

echo "[4/10] Running Redex optimization..."
"$REDEX" -i "$WORKDIR/stripped.apk" -o "$WORKDIR/redexed.apk"

echo "[5/10] Converting DEX to JAR for ProGuard/R8..."
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
  -libraryjars \
  -include "$WORKDIR/proguard-rules.pro" < java.home > /lib/rt.jar

echo "[7/10] Rebuilding DEX from optimized JAR..."
# Convert back: jar2dex
dx --dex --output="$WORKDIR/classes.dex" "$WORKDIR/app_proguard.jar"
# Repackage into APK
unzip -q "$WORKDIR/redexed.apk" -d "$WORKDIR/apk_unpack"
cp "$WORKDIR/classes.dex" "$WORKDIR/apk_unpack/"
cd "$WORKDIR/apk_unpack" || exit
zip -q -r ../repackaged.apk .
cd - > /dev/null || exit

echo "[8/10] Aligning APK..."
"$ZIPALIGN" -v -p 4 "$WORKDIR/repackaged.apk" "$WORKDIR/aligned.apk"

echo "[9/10] Signing APK..."
"$APKSIGNER" sign \
  --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" \
  --ks-pass pass:"$KEYSTORE_PASS" --key-pass pass:"$KEY_PASS" \
  --out "$WORKDIR/signed.apk" \
  "$WORKDIR/aligned.apk"

echo "[10/10] Optimizing PNGs and JPEGs..."
# Unzip to optimize resources
unzip -q "$WORKDIR/signed.apk" -d "$WORKDIR/final_unpack"
find "$WORKDIR/final_unpack/res" -iname "*.png" -exec "$PNGCRUSH" -rem alla -brute {} {}.opt \; -exec mv {}.opt {} +
find "$WORKDIR/final_unpack/res" -iname "*.jpg" -exec "$JPEGOPTIM" --strip-all {} +
# Rezip final APK
cd "$WORKDIR/final_unpack" || exit
"$SEVENZIP" a -tzip -mx=9 ../"$OUTPUT_APK" .
cd - > /dev/null || exit

echo "✅ Optimized APK created at: $WORKDIR/$OUTPUT_APK"
