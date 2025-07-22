# After your build step (where you already built the APK):
APK_PATH="target/release/app-unsigned.apk"
OPT_APK="target/release/app-optimized.apk"

if command -v aapt2 >/dev/null; then
  echo "[AAPT2] Optimizing resources..."
  # Compile resources into .flat for better compression
  aapt2 compile --dir res -o compiled-res.zip

  # Link
  aapt2 link -o linked-res.apk -I "$ANDROID_HOME/platforms/android-34/android.jar" \
    --manifest AndroidManifest.xml --java gen --proguard proguard.txt compiled-res.zip

  # Optimize final APK (strip locales, crunch PNGs, flatten resources)
  aapt2 optimize \
    --collapse-resource-names \
    --shorten-resource-paths \
    --resources-config-path proguard.txt \
    --enable-sparse-encoding \
    -o "$OPT_APK" "$APK_PATH"

  echo "[AAPT2] Optimized APK saved to $OPT_APK"
else
  echo "[WARN] aapt2 not found, skipping resource optimization."
fi
