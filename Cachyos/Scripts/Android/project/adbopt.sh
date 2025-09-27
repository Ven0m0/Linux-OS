#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

# --- Configuration & Setup ---

# Ensure consistent script behavior regardless of user's locale.
export LC_ALL=C LANG=C

# Check for required command-line tools.
check_deps() {
  if ! command -v adb &>/dev/null; then
    printf '%s\n' "adb not found. Attempting to install android-tools..."
    if command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm --needed android-tools
    elif command -v apt-get &>/dev/null; then
      sudo apt-get install -yq android-tools-adb
    else
      printf '%s\n' "Error: Could not find a known package manager (pacman, apt-get) to install android-tools." >&2
      exit 1
    fi
  fi
}

# --- Device Maintenance ---

apply_maintenance() {
  printf '%s\n' "## Performing Maintenance..."
  adb shell sync
  adb shell cmd stats write-to-disk
  adb shell settings put global fstrim_mandatory_interval 1
  adb shell pm art cleanup
  adb shell pm trim-caches 128G # Note: 128G might be excessive for some devices
  adb shell cmd shortcut reset-all-throttling
  adb shell logcat -b all -c
  adb shell wm density reset
  adb shell wm size reset
  adb shell sm fstrim
  adb shell cmd activity idle-maintenance
  adb shell cmd system_update
  adb shell cmd otadexopt cleanup
  # The following commands likely require root access
  # adb shell wipe cache
  # adb shell recovery --wipe_cache
}

# --- Filesystem Cleanup ---

apply_cleanup() {
  printf '%s\n' "## Cleaning temporary files on device..."
  # Use find for more reliable deletion within the device's shell
  #adb shell 'find /sdcard /storage /cache /data/local -type f \( -name "*.tmp" -o -name "*.log" -o -name "*.bak" \) -delete'
  adb shell find . -type f -o -name "*.log" -delete
  adb shell find . -type f -o -name "*.old" -delete
  adb shell find . -type f -o -name "*.tmp" -delete
  adb shell find . -type f -o -name "*.bak" -delete
}

# --- ART Optimization ---

optimize_art() {
  printf '%s\n' "## Optimizing ART (Android Runtime)..."
  # Run any postponed dex-opt jobs immediately
  local job_id
  job_id=$(adb shell cmd jobscheduler list-jobs android | grep 'background-dexopt' | awk '{print $2}')
  if [[ -n "$job_id" ]]; then
    adb shell cmd jobscheduler run -f android "$job_id"
  fi

  # Compile all packages with 'speed-profile', then 'speed' for wider coverage.
  adb shell cmd package compile -af --full --secondary-dex -m speed-profile
  adb shell cmd package compile -a -f --full --secondary-dex -m speed
  adb shell pm art dexopt-packages -r bg-dexopt
}

# --- System & Performance Tweaks ---

apply_performance_tweaks() {
  printf '%s\n' "## Applying Performance tweaks..."
  adb shell setprop debug.performance.tuning 1
  adb shell setprop debug.mdpcomp.enable 1
  adb shell settings put global sqlite_compatibility_wal_flags "syncMode=OFF,fsyncMode=off"
  adb shell device_config put graphics enable_cpu_boost true
  adb shell device_config put graphics enable_gpu_boost true
  adb shell device_config put graphics render_thread_priority high
  adb shell device_config put activity_manager force_high_refresh_rate true
  adb shell device_config put activity_manager enable_background_cpu_boost true
  adb shell device_config put activity_manager use_compaction true
  adb shell device_config put privacy location_access_check_enabled false
  adb shell device_config put privacy location_accuracy_enabled false
  adb shell device_config put runtime_native_boot pin_camera false
  adb shell device_config put launcher ENABLE_QUICK_LAUNCH_V2 true
}

# --- Rendering & Graphics Tweaks ---

apply_rendering_tweaks() {
  printf '%s\n' "## Applying Rendering tweaks..."
  # Use setprop for transient properties
  adb shell setprop debug.composition.type dyn
  adb shell setprop debug.fb.rgb565 0
  adb shell setprop debug.sf.disable_threaded_present false
  adb shell setprop debug.sf.predict_hwc_composition_strategy 1
  adb shell setprop debug.hwui.use_buffer_age true
  adb shell setprop debug.sf.gpu_comp_tiling 1
  adb shell setprop debug.enable.sglscale 1
  adb shell setprop debug.sdm.support_writeback 1
  adb shell setprop debug.sf.disable_client_composition_cache 0
  adb shell setprop debug.sf.use_phase_offsets_as_durations 1
  adb shell setprop debug.sf.enable_gl_backpressure 1
  adb shell setprop debug.sf.enable_advanced_sf_phase_offset 1
  adb shell setprop debug.egl.native_scaling 1
  adb shell setprop debug.egl.hw 1
  adb shell setprop debug.sf.hw 1
  adb shell setprop debug.sf.no_hw_vsync 1
  adb shell setprop debug.sf.ddms 0
  adb shell setprop debug.sf.enable_hgl 1
  adb shell setprop debug.sf.enable_hwc_vds 0
  adb shell setprop debug.gfx.driver 1
  adb shell setprop debug.sf.perf_mode 1
  adb shell setprop debug.enabletr true
  adb shell setprop debug.qc.hardware true
  adb shell setprop debug.hwui.use_gpu_pixel_buffers false
  adb shell setprop debug.hwui.renderer_mode 1
  adb shell setprop debug.hwui.disabledither true
  adb shell setprop debug.hwui.enable_bp_cache true
  adb shell setprop debug.gralloc.map_fb_memory 1
  adb shell setprop debug.gralloc.enable_fb_ubwc 1
  adb shell setprop debug.gralloc.gfx_ubwc_disable 0
  adb shell setprop debug.gralloc.disable_hardware_buffer 1
  adb shell setprop debug.smart_scheduling 1
  adb shell setprop debug.hwui.disable_gpu_cache false
  adb shell setprop debug.gr.swapinterval 0
  adb shell setprop debug.egl.swapinterval 0
  adb shell setprop debug.slsi_platform 1
  adb shell setprop debug.sqlite.journalmode OFF
  adb shell setprop debug.sqlite.syncmode OFF
  adb shell setprop debug.sqlite.wal.syncmode ON
  adb shell setprop debug.stagefright.ccodec 1
  adb shell setprop debug.syncopts 3
  adb shell setprop debug.threadedOpt 1

  # Use 'settings put' for persistent settings
  adb shell settings put global force_gpu_rendering 1
  adb shell settings put global hardware_accelerated_rendering_enabled 1
  adb shell settings put global overlay_disable_force_hwc 1
  adb shell settings put global disable_hw_overlays 1
  adb shell settings put global video.accelerate.hw 1
  adb shell settings put global media.sf.hwaccel 1
  adb shell settings put global hw2d.force 1
  adb shell settings put global hw3d.force 1
  adb shell settings put global multi_sampling_enabled 0
  adb shell settings put global sysui_font_cache_persist true
  adb shell settings put global gpu_rasterization_forced 1
  adb shell settings put global enable_lcd_text 1
  adb shell settings put global renderthread.skia.reduceopstasksplitting true
  adb shell settings put global skia.force_gl_texture 1
}

# --- Audio Tweaks ---

apply_audio_tweaks() {
  printf '%s\n' "## Applying Audio tweaks..."
  adb shell settings put global audio.deep_buffer.media true
  adb shell settings put global audio.parser.ip.buffer.size 0
  adb shell settings put global audio.offload.video true
  adb shell settings put global audio.offload.track.enable true
  adb shell settings put global audio.offload.passthrough false
  adb shell settings put global audio.offload.gapless.enabled true
  adb shell settings put global audio.offload.multiple.enabled true
  adb shell settings put global audio.offload.pcm.16bit.enable false
  adb shell settings put global audio.offload.pcm.24bit.enable false
  adb shell settings put global media.enable-commonsource true
  adb shell settings put global media.stagefright.thumbnail.prefer_hw_codecs true
  adb shell settings put global media.stagefright.use-awesome true
  adb shell settings put global media.stagefright.enable-record false
  adb shell settings put global media.stagefright.enable-scan false
  adb shell settings put global media.stagefright.enable-meta true
  adb shell settings put global media.stagefright.enable-http true
  adb shell setprop debug.media.video.frc false
  adb shell setprop debug.media.video.vpp false
}

# --- Battery & Power Saving ---

apply_battery_tweaks() {
  printf '%s\n' "## Applying Battery tweaks..."
  local battery_saver_constants
  battery_saver_constants="vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,fullbackup_deferred=true,keyvaluebackup_deferred=true,gps_mode=low_power,data_saver=true,optional_sensors_disabled=true,advertiser_id_enabled=false"

  adb shell settings put global battery_saver_constants "$battery_saver_constants"
  adb shell settings put global dynamic_power_savings_enabled 1
  adb shell settings put global adaptive_battery_management_enabled 0
  adb shell settings put global app_auto_restriction_enabled 1
  adb shell settings put global cached_apps_freezer enabled
  adb shell settings put global allow_heat_cooldown_always 1
  adb shell settings put global ram_expand_size_list 1
  adb shell settings put global native_memtag_sync 1
  adb shell settings put global background_gpu_usage 0
  adb shell settings put global enable_app_prefetch 1
  adb shell settings put global storage.preload.complete 1
  adb shell settings put global ota_disable_automatic_update 1

  adb shell cmd power suppress-ambient-display true
  adb shell cmd power set-face-down-detector false
  adb shell cmd power set-fixed-performance-mode-enabled false
  adb shell cmd power set-adaptive-power-saver-enabled true
  adb shell settings put system accelerometer_rotation 0
}

# --- Input & Animation Tweaks ---

apply_input_tweaks() {
  printf '%s\n' "## Applying Input & Animation tweaks..."
  adb shell settings put global animator_duration_scale 0.0
  adb shell settings put global transition_animation_scale 0.0
  adb shell settings put global window_animation_scale 0.0
  adb shell settings put secure long_press_timeout 250
  adb shell settings put secure multi_press_timeout 250
  adb shell settings put secure tap_duration_threshold 0.0
  adb shell settings put secure touch_blocking_period 0.0
  adb shell wm disable-blur true
}

# --- Network Tweaks ---

apply_network_tweaks() {
  printf '%s\n' "## Applying Network tweaks..."
  adb shell cmd netpolicy set restrict-background true
  adb shell settings put global data_saver_mode 1
  adb shell settings put global ro.wifi.signal.optimized true
  adb shell settings put global multipath-tcp-enable 1
  adb shell settings put global mobile_data_always_on 0
  adb shell settings put global wifi_scan_always_enabled 0
  adb shell settings put global ble_scan_always_enabled 0
  adb shell settings put global network_avoid_bad_wifi 1
  adb shell settings put global wifi_suspend_optimizations_enabled 2
  adb shell settings put global webview_safe_browsing_enabled 0
  # Note: Add your preferred DNS here
  # adb shell settings put global private_dns_mode hostname
  # adb shell settings put global private_dns_specifier 'dns.adguard.com'
}

# --- Webview & ANGLE ---

configure_webview_angle() {
  printf '%s\n' "## Configuring Webview and ANGLE..."
  # This may require root on the device
  # adb shell 'echo "webview --enable-features=DeferImplInvalidation,ScrollUpdateOptimizations" > /data/local/tmp/webview-command-line'
  # adb shell 'chmod 644 /data/local/tmp/webview-command-line'

  # Set WebView implementation (replace with desired package)
  adb shell cmd webviewupdate set-webview-implementation com.android.webview.beta

  # Enable ANGLE for selected packages
  adb shell settings put global angle_gl_driver_all_angle 1
  adb shell settings put global angle_debug_package com.android.angle
  adb shell settings put global angle_gl_driver_selection_values angle
  adb shell settings put global angle_gl_driver_selection_pkgs com.android.webview,com.android.webview.beta
}

# --- Miscellaneous Settings ---

apply_misc_tweaks() {
  printf '%s\n' "## Applying Miscellaneous tweaks..."
  adb shell setprop debug.debuggerd.disable 1
  adb shell settings put secure USAGE_METRICS_UPLOAD_ENABLED 0
  adb shell settings put system send_security_reports 0
  adb shell device_config put systemui window_shadow 0
  adb shell device_config put systemui window_blur 0
  adb shell device_config put systemui window_cornerRadius 0
}

# --- Main Execution Logic ---

main() {
  check_deps

  printf '%s\n' "## Starting Android Optimization Script..."

  # Verify device connection
  if ! adb get-state 1>/dev/null 2>&1; then
    printf "Error: No device found. Please connect a device and enable USB debugging.\n" >&2
    exit 1
  fi
  if [[ "$(adb get-state)" != "device" ]]; then
    printf "Error: Device not authorized. Please check your device to allow USB debugging.\n" >&2
    exit 1
  fi

  adb start-server
  printf "Connected devices:\n"
  adb devices

  # Run all optimization functions
  apply_maintenance
  apply_cleanup
  optimize_art
  apply_performance_tweaks
  apply_rendering_tweaks
  apply_audio_tweaks
  apply_battery_tweaks
  apply_input_tweaks
  apply_network_tweaks
  configure_webview_angle
  apply_misc_tweaks

  # Final cleanup and state setting
  printf '%s\n' "## Finalizing..."
  adb shell am broadcast -a android.intent.action.ACTION_OPTIMIZE_DEVICE
  adb shell pm bg-dexopt-job
  adb shell am kill-all
  adb shell cmd activity kill-all
  adb shell dumpsys batterystats --reset
  adb shell clean_scratch_files
  adb shell update_engine_client --update
  adb shell e2freefrag
  printf '%s\n' "## All done!"

  # Optional: kill server and clean local adb files
  # adb kill-server
  # rm -rf "${HOME}/.android"
}

# Ensure the script is executed directly, not sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
