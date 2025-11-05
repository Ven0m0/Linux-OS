#!/usr/bin/env bash
# Android App-Specific Optimizer
# Optimizes specific apps with targeted compilation modes for best performance

set -euo pipefail
export LC_ALL=C LANG=C

# Check if adb is available
if ! command -v adb &>/dev/null; then
  echo "Error: adb not found. Please install android-tools." >&2
  exit 1
fi

printf '%s\n' "Starting ADB server..."
adb start-server

# Verify device connection
if ! adb get-state 1>/dev/null 2>&1; then
  printf "Error: No device found. Please connect a device and enable USB debugging.\n" >&2
  exit 1
fi

# --- System Properties ---
printf '%s\n' "## Configuring system properties..."
adb shell setprop debug.enabletr 1
adb shell setprop debug.sf.hw 1
adb shell setprop debug.egl.hw 1
adb shell setprop debug.performance.tuning 1
adb shell setprop debug.composition.type c2d
adb shell setprop debug.renderengine.backend skiaglthreaded
adb shell setprop debug.hwui.renderer skiagl
adb shell setprop debug.fb.rgb565 0
adb shell setprop debug.egl.profiler 0
adb shell setprop debug.debuggerd.disable 1
adb shell setprop debug.tracing.screen_state 0
adb shell setprop debug.tracing.mnc 0
adb shell setprop debug.sf.enable_egl_image_tracker 0
adb shell setprop debug.mdpcomp.logs 0
adb shell setprop debug.mdpcomp.enable 1
adb shell setprop debug.enable_dmabuf 1
adb shell setprop debug.sf.predict_hwc_composition_strategy 1
adb shell setprop debug.hwui.use_buffer_age true
adb shell setprop debug.atrace.tags.enableflags 0

# --- Initial Cleanup ---
printf '%s\n' "## Performing initial cleanup..."
adb shell pm art cleanup
adb shell pm trim-caches 999999999999999999

# --- Compile All Apps (Speed-Profile) ---
printf '%s\n' "## Compiling all apps with speed-profile..."
adb shell cmd package compile -a -f --full --secondary-dex -m speed-profile

# --- High-Performance Apps (Speed mode) ---
printf '%s\n' "## Optimizing high-performance apps..."

declare -a SPEED_APPS=(
  # Social Media & Communication
  "com.whatsapp"
  "com.snapchat.android"
  "com.instagram.android"
  "com.zhiliaoapp.musically"  # TikTok

  # Entertainment
  "app.revanced.android.youtube"
  "anddea.youtube.music"
  "com.spotify.music"

  # Messaging & Productivity
  "com.feelingtouch.rtd"
  "app.revenge"

  # Games
  "com.supercell.clashroyale"

  # Audio
  "com.pittvandewitt.wavelet"

  # Health
  "com.freestylelibre3.app.de"

  # Camera & Media
  "com.nothing.camera"
  "com.android.htmlviewer"
  "com.android.providers.media"
)

for app in "${SPEED_APPS[@]}"; do
  printf "  Compiling: %s\n" "$app"
  adb shell cmd package compile -f --full --secondary-dex -m speed "$app" 2>/dev/null || true
done

# --- Critical System Apps (Everything mode) ---
printf '%s\n' "## Optimizing critical system components..."

declare -a SYSTEM_APPS=(
  # System UI & Launcher
  "com.android.systemui"
  "com.nothing.launcher"
  "com.android.internal.systemui.navbar.threebutton"

  # WebView & Input
  "com.google.android.webview"
  "com.google.android.webview.beta"
  "com.google.android.inputmethod.latin"

  # Core Services
  "com.android.providers.settings"
  "com.android.server.telecom"
  "com.android.location.fused"
  "com.mediatek.location.lppe.main"
  "com.google.android.permissioncontroller"
  "com.android.bluetooth"
)

for app in "${SYSTEM_APPS[@]}"; do
  printf "  Compiling: %s\n" "$app"
  adb shell cmd package compile -f --full --secondary-dex -m everything "$app" 2>/dev/null || true
done

# --- Final Optimization ---
printf '%s\n' "## Running final optimization passes..."
adb shell pm art dexopt-packages -r bg-dexopt
adb shell pm art cleanup
adb shell pm trim-caches 999999999999999999
adb shell pm trim-caches 999999999999999999

printf '%s\n' "## App optimization complete!"
adb kill-server
