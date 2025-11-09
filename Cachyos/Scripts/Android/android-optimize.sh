#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'; export LC_ALL=C LANG=C

# Unified Android optimizer (desktop Linux or Termux host)
# Combines: adb-device-optimizer, adb-app-optimizer, monolith, cleanup, nomedia, WA cleaner, aapt2 optimize

ADB_BIN="${ADB:-adb}"
FD="${FD:-$(command -v fd || command -v fdfind || true)}"
RG="${RG:-$(command -v rg || true)}"
SD="${SD:-$(command -v sd || true)}"
FIND="${FIND:-$(command -v find)}"
CUT="${CUT:-$(command -v cut)}"
XARGS="${XARGS:-$(command -v xargs)}"

SPEED_APPS=(
  com.whatsapp com.snapchat.android com.instagram.android com.zhiliaoapp.musically
  app.revanced.android.youtube anddea.youtube.music com.spotify.music
  com.feelingtouch.rtd app.revenge com.supercell.clashroyale
  com.pittvandewitt.wavelet com.freestylelibre3.app.de
  com.nothing.camera com.android.htmlviewer com.android.providers.media
)
SYSTEM_APPS=(
  com.android.systemui com.nothing.launcher com.android.internal.systemui.navbar.threebutton
  com.google.android.webview com.google.android.webview.beta com.google.android.inputmethod.latin
  com.android.providers.settings com.android.server.telecom com.android.location.fused
  com.mediatek.location.lppe.main com.google.android.permissioncontroller com.android.bluetooth
)

aapt2_detect_android_jar(){
  local roots=()
  [[ -n "${ANDROID_HOME:-}" ]] && roots+=("$ANDROID_HOME")
  [[ -n "${ANDROID_SDK_ROOT:-}" ]] && roots+=("$ANDROID_SDK_ROOT")
  roots+=("$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/opt/android-sdk")
  local jar=""
  for root in "${roots[@]}"; do
    [[ -d "$root/platforms" ]] || continue
    local c v
    while IFS= read -r -d '' c; do
      v="${c##*/}"
      [[ -f "$c/android.jar" ]] && jar="$c/android.jar"
    done < <("$FIND" "$root/platforms" -maxdepth 1 -type d -name "android-*" -print0 2>/dev/null || :)
    [[ -n "$jar" ]] && break
  done
  printf '%s\n' "${jar:-}"
}

adb_ok(){
  command -v "$ADB_BIN" &>/dev/null || { printf 'adb not found\n' >&2; exit 1; }
  "$ADB_BIN" start-server &>/dev/null || :
  "$ADB_BIN" get-state &>/dev/null || { printf 'No device. Enable USB debugging.\n' >&2; exit 1; }
}

ash(){ "$ADB_BIN" shell "$@" 2>/dev/null || :; }

section(){ printf '\n== %s ==\n' "$*"; }

maintenance(){
  section "Maintenance"
  ash sync
  ash cmd stats write-to-disk
  ash settings put global fstrim_mandatory_interval 1
  ash pm art cleanup
  ash pm trim-caches 128G
  ash cmd shortcut reset-all-throttling
  ash logcat -b all -c
  ash wm density reset
  ash wm size reset
  ash sm fstrim
  ash cmd activity idle-maintenance
  ash cmd system_update
  ash cmd otadexopt cleanup
}

cleanup_fs(){
  section "Cleanup"
  # Safer targeted cleanup; avoid rm -rf in critical dirs
  ash 'find /sdcard -type f -iregex ".*\.\(log\|bak\|old\|tmp\)$" -delete'
  ash 'find /storage -mindepth 2 -maxdepth 5 -type f -iregex ".*\.\(log\|bak\|old\|tmp\)$" -delete'
}

opt_art(){
  section "ART Optimize"
  local job_id
  job_id="$("$ADB_BIN" shell cmd jobscheduler list-jobs android 2>/dev/null | grep -F background-dexopt | awk "{print \$2}" || true)"
  [[ -n "${job_id:-}" ]] && ash cmd jobscheduler run -f android "$job_id"
  ash cmd package compile -af --full --secondary-dex -m speed-profile
  ash cmd package compile -a -f  --full --secondary-dex -m speed
  ash pm art dexopt-packages -r bg-dexopt
}

tweaks_perf(){
  section "Performance"
  ash setprop debug.performance.tuning 1
  ash setprop debug.mdpcomp.enable 1
  ash device_config put graphics enable_cpu_boost true
  ash device_config put graphics enable_gpu_boost true
  ash device_config put graphics render_thread_priority high
  ash device_config put activity_manager force_high_refresh_rate true
  ash device_config put activity_manager enable_background_cpu_boost true
  ash device_config put activity_manager use_compaction true
  ash device_config put privacy location_access_check_enabled false
  ash device_config put privacy location_accuracy_enabled false
}

tweaks_render(){
  section "Rendering"
  ash setprop debug.composition.type dyn
  ash setprop debug.fb.rgb565 0
  ash setprop debug.sf.predict_hwc_composition_strategy 1
  ash setprop debug.hwui.use_buffer_age true
  ash setprop debug.sf.gpu_comp_tiling 1
  ash setprop debug.enable.sglscale 1
  ash setprop debug.sf.use_phase_offsets_as_durations 1
  ash setprop debug.sf.enable_gl_backpressure 1
  ash setprop debug.egl.hw 1
  ash setprop debug.sf.hw 1
  ash setprop debug.gfx.driver 1
  ash setprop debug.enabletr true
  ash setprop debug.hwui.renderer_mode 1
  ash settings put global force_gpu_rendering 1
  ash settings put global disable_hw_overlays 1
  ash settings put global gpu_rasterization_forced 1
}

tweaks_audio(){
  section "Audio"
  ash settings put global audio.offload.video true
  ash settings put global audio.offload.track.enable true
  ash settings put global audio.offload.gapless.enabled true
  ash settings put global audio.offload.multiple.enabled true
  ash settings put global media.stagefright.thumbnail.prefer_hw_codecs true
}

tweaks_battery(){
  section "Battery"
  ash settings put global dynamic_power_savings_enabled 1
  ash settings put global adaptive_battery_management_enabled 0
  ash settings put global app_auto_restriction_enabled 1
  ash settings put global cached_apps_freezer enabled
  ash cmd power suppress-ambient-display true
  ash cmd power set-fixed-performance-mode-enabled false
  ash cmd power set-adaptive-power-saver-enabled true
}

tweaks_input(){
  section "Input/Animations"
  ash settings put global animator_duration_scale 0.0
  ash settings put global transition_animation_scale 0.0
  ash settings put global window_animation_scale 0.0
  ash wm disable-blur true
}

tweaks_net(){
  section "Network"
  ash cmd netpolicy set restrict-background true
  ash settings put global data_saver_mode 1
  ash settings put global mobile_data_always_on 0
  ash settings put global wifi_scan_always_enabled 0
  ash settings put global ble_scan_always_enabled 0
  ash settings put global network_avoid_bad_wifi 1
}

tweaks_angle_webview(){
  section "WebView/ANGLE"
  ash cmd webviewupdate set-webview-implementation com.android.webview.beta
  ash settings put global angle_gl_driver_all_angle 1
  ash settings put global angle_debug_package com.android.angle
  ash settings put global angle_gl_driver_selection_values angle
  ash settings put global angle_gl_driver_selection_pkgs com.android.webview,com.android.webview.beta
}

tweaks_misc(){
  section "Misc"
  ash setprop debug.debuggerd.disable 1
  ash settings put secure USAGE_METRICS_UPLOAD_ENABLED 0
  ash settings put system send_security_reports 0
  ash device_config put systemui window_shadow 0
  ash device_config put systemui window_blur 0
}

apps_compile_speed(){
  section "High-Perf Apps → speed"
  for p in "${SPEED_APPS[@]}"; do
    printf '  %s\n' "$p"
    ash cmd package compile -f --full --secondary-dex -m speed "$p"
  done
}

apps_compile_system_everything(){
  section "System Apps → everything"
  for p in "${SYSTEM_APPS[@]}"; do
    printf '  %s\n' "$p"
    ash cmd package compile -f --full --secondary-dex -m everything "$p"
  done
}

finalize(){
  section "Finalize"
  ash am broadcast -a android.intent.action.ACTION_OPTIMIZE_DEVICE
  ash pm bg-dexopt-job
  ash am kill-all
  ash cmd activity kill-all
  ash dumpsys batterystats --reset
}

cmd_device_all(){
  adb_ok
  maintenance
  cleanup_fs
  opt_art
  tweaks_perf
  tweaks_render
  tweaks_audio
  tweaks_battery
  tweaks_input
  tweaks_net
  tweaks_angle_webview
  tweaks_misc
  apps_compile_speed
  apps_compile_system_everything
  finalize
  printf 'Done.\n'
}

cmd_monolith(){
  adb_ok
  local mode="${1:-everything-profile}"
  section "Monolith ($mode)"
  ash cmd package compile -a -f -m "$mode"
  ash cmd package compile -a -f --compile-layouts
  ash cmd package bg-dexopt-job
  printf 'Done.\n'
}

cmd_cache_clean(){
  adb_ok
  section "Clear per-app caches"
  "$ADB_BIN" shell pm list packages -3 2>/dev/null | "$CUT" -d: -f2 \
    | "$XARGS" -r -n1 -P"$(nproc)" -I{} "$ADB_BIN" shell pm clear --cache-only {} &>/dev/null || :
  "$ADB_BIN" shell pm list packages -s 2>/dev/null | "$CUT" -d: -f2 \
    | "$XARGS" -r -n1 -P"$(nproc)" -I{} "$ADB_BIN" shell pm clear --cache-only {} &>/dev/null || :
  ash pm trim-caches 128G
  ash logcat -b all -c
  printf 'Done.\n'
}

cmd_index_nomedia(){
  local base="${1:-/storage/emulated/0}"
  section "Index guard (.nomedia, .noindex)"
  while IFS= read -r -d '' d; do
    : >"$d/.nomedia" || :
    : >"$d/.noindex" || :
    : >"$d/.metadata_never_index" || :
    : >"$d/.trackerignore" || :
  done < <("$FIND" "$base" -type d -readable -print0 2>/dev/null)
  printf 'Done.\n'
}

cmd_wa_clean(){
  local wa="${1:-/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media}"
  section "WhatsApp cleanup (>45d)"
  [[ -d "$wa" ]] || { printf 'Path not found: %s\n' "$wa" >&2; return 0; }
  local before after
  before=$(du -sm "$wa" 2>/dev/null | "$CUT" -f1 || printf '0')
  "$FIND" "$wa" -type f -iregex '.*\.\(jpg\|jpeg\|png\|gif\|mp4\|mov\|wmv\|flv\|webm\|mxf\|avi\|avchd\|mkv\)$' -mtime +45 -print0 \
    | xargs -0 -r rm -f
  after=$(du -sm "$wa" 2>/dev/null | "$CUT" -f1 || printf '0')
  printf 'Freed: %d MB\n' "$((before-after))"
}

cmd_aapt2_opt(){
  local in="${1:-target/release/app-unsigned.apk}"
  local out="${2:-target/release/app-optimized.apk}"
  section "AAPT2 optimize"
  command -v aapt2 &>/dev/null || { printf 'aapt2 not found\n' >&2; return 1; }
  local android_jar; android_jar="$(aapt2_detect_android_jar)"
  [[ -f "$android_jar" ]] || { printf 'android.jar not found\n' >&2; return 1; }
  mkdir -p "$(dirname "$out")"
  aapt2 compile --dir res -o compiled-res.zip &>/dev/null || :
  aapt2 link -o linked-res.apk -I "$android_jar" --manifest AndroidManifest.xml --java gen compiled-res.zip &>/dev/null || :
  aapt2 optimize --collapse-resource-names --shorten-resource-paths --enable-sparse-encoding -o "$out" "$in"
  printf 'Saved → %s\n' "$out"
}

usage(){
  cat <<EOF
android-optimize.sh
  device-all                Run full device optimization pipeline
  monolith [mode]           Compile all (default: everything-profile) + layouts + bg job
  cache-clean               Clear app caches (3rd+system), trim, clear logcat
  index-nomedia [base]      Touch .nomedia/.noindex recursively (default /storage/emulated/0)
  wa-clean [path]           Cleanup WhatsApp media older than 45d
  aapt2-opt [in] [out]      Optimize APK with aapt2

Examples:
  $0 device-all
  $0 monolith speed-profile
  $0 index-nomedia
  $0 wa-clean
  $0 aapt2-opt app.apk app-optimized.apk
EOF
}

main(){
  local cmd="${1:-}"; shift || true
  case "${cmd:-}" in
    device-all) cmd_device_all "$@";;
    monolith) cmd_monolith "$@";;
    cache-clean) cmd_cache_clean "$@";;
    index-nomedia) cmd_index_nomedia "$@";;
    wa-clean) cmd_wa_clean "$@";;
    aapt2-opt) cmd_aapt2_opt "$@";;
    ""|-h|--help) usage;;
    *) printf 'Unknown: %s\n' "$cmd" >&2; usage; exit 2;;
  esac
}
main "$@"