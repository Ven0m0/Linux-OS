#!/usr/bin/env bash
# device_config_manager.sh - Manage Android device configurations via ADB
# Can be integrated into android-toolkit.sh or used standalone

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C

# Helper functions
log(){
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

check_adb(){
  command -v adb &>/dev/null>/dev/null || {
    echo "Error: adb not found. Please install Android platform tools."
    return 1
  }
  adb get-state &>/dev/null>/dev/null || {
    echo "Error: No device connected or unauthorized."
    return 1
  }
}

# Apply all optimized config settings to the connected device
apply_device_configs(){
  local section key value
  log "Applying optimized device configurations..."

  # Connectivity settings
  apply_config connectivity dhcp_rapid_commit_enabled true

  # Privacy settings
  apply_config privacy bg_location_check_is_enabled false
  apply_config privacy safety_center_is_enabled false
  #apply_config privacy location_accuracy_enabled true

  # Runtime settings
  apply_config runtime force_disable_pr_dexopt false
  apply_config runtime_native metrics.write-to-statsd false
  apply_config runtime_native use_app_image_startup_cache true
  apply_config runtime_native_boot use_generational_gc true
  apply_config runtime_native_boot iorap_readahead_enable true

  # System UI settings
  apply_config systemui notification_memory_logging_enabled false

  # Activity manager settings
  apply_config activity_manager bg_current_drain_auto_restrict_abusive_apps_enabled true
  apply_config activity_manager use_compaction true
  apply_config activity_manager force_high_refresh_rate true
  apply_config activity_manager enable_background_cpu_boost true

  # Package manager settings
  apply_config package_manager_service Archiving__enable_archiving true

  # Window manager settings
  #apply_config window_manager enable_non_linear_font_scaling false
  apply_config window_manager android.adaptiveauth.report_biometric_auth_attempts false

  # WiFi settings
  apply_config wifi com.android.wifi.flags.improve_ranging_api true
  apply_config wifi com.android.wifi.flags.local_only_connection_optimization true
  #apply_config wifi com.android.wifi.flags.single_wifi_thread false
  apply_config wifi com.android.wifi.flags.scan_optimization_with_mobility_change true
  apply_config wifi com.android.wifi.flags.band_optimization_control true

  # Bluetooth settings - optimize but disable features that might drain battery
  for flag in a2dp_lhdc_api a2dp_variable_aac_capability a2dp_version_1_4 avdt_prioritize_mandatory_codec \
    avrcp_16_default brcm_better_le_scan_params browsing_refactor bt_socket_api_l2cap_cid \
    enable_sniff_offload fix_buf_len_check_for_first_k_frame fix_hfp_qual_1_9 \
    fix_started_module_race hh_state_update_race_fix l2cap_fcs_option_fix; do
    apply_config bluetooth "com.android.bluetooth.flags.${flag}" true
  done

  # Ad services (disable features that might collect data)
  apply_config adservices adservice_enabled false
  apply_config adservices adservice_error_logging_enabled false
  apply_config adservices adservice_system_service_enabled false
  apply_config adservices cobalt_logging_enabled false
  apply_config adservices consent_manager_lazy_enable_mode true
  apply_config adservices disable_fledge_enrollment_check true
  apply_config adservices enable_ad_services_system_api false

  # Additional system commands
  apply_system_commands

  log "Device configurations applied successfully"
}

# Apply config settings for a specific section
apply_config(){
  local section="$1" key="$2" value="$3"
  log_debug "Setting ${section}/${key}=${value}"
  adb shell cmd device_config put "$section" "$key" "$value" >/dev/null 2>&1 \
    || log "Failed to set ${section}/${key}=${value}"
}

# Apply additional system commands that aren't device_config settings
apply_system_commands(){
  log "Applying system commands..."

  # WiFi settings
  adb shell cmd wifi set-scan-always-available disabled
  adb shell cmd -w wifi force-country-code enabled DE
  adb shell cmd -w wifi force-low-latency-mode enabled
  adb shell cmd wifi force-low-latency-mode enabled
  adb shell cmd -w wifi force-hi-perf-mode enabled
  adb shell cmd wifi force-hi-perf-mode enabled

  # Thermal settings
  adb shell cmd thermalservice reset

  # Telecom settings
  adb shell cmd telecom cleanup-orphan-phone-accounts
  adb shell cmd telecom cleanup-stuck-calls
  adb shell cmd telecom set-metrics-test-disabled

  # Display settings
  adb shell cmd display ab-logging-disable
  adb shell cmd display dwb-logging-disable
  adb shell cmd display dmd-logging-disable
  adb shell cmd display set-brightness 50

  # Activity management
  adb shell device_config put activity_manager use_compaction true
  adb shell device_config put activity_manager enable_background_cpu_boost true
  adb shell device_config put activity_manager force_high_refresh_rate true
  adb shell device_config put graphics render_thread_priority high

  adb shell cmd activity kill-all
  adb shell am kill-all
  adb shell cmd activity compact system
  adb shell am broadcast -a android.intent.action.ACTION_OPTIMIZE_DEVICE
  adb shell am broadcast -a com.android.systemui.action.CLEAR_MEMORY

  # Network policy
  adb shell cmd netpolicy set restrict-background true

  # Package optimization
  adb shell settings put global fstrim_mandatory_interval 1
  adb shell sync
  adb shell cmd stats write-to-disk
  adb shell cmd shortcut reset-all-throttling
  adb shell pm trim-caches 128G
  adb shell logcat -c
  adb shell sm fstrim
  adb shell cmd activity idle-maintenance
  adb shell pm bg-dexopt-job

  adb shell cmd otadexopt cleanup
  adb shell cmd package art pr-dexopt-job --run
  adb shell cmd package art configure-batch-dexopt -r bg-dexopt
  adb shell cmd package art dexopt-packages -r bg-dexopt
  adb shell pm bg-dexopt-job
  adb shell cmd package art cleanup
  adb shell cmd package compile -p PRIORITY_INTERACTIVE_FAST --force-merge-profile --full -a -r cmdline -m speed
  adb shell cmd package compile -r bg-dexopt -a
  adb shell am broadcast -a android.intent.action.ACTION_OPTIMIZE_DEVICE
  adb shell am broadcast -a com.android.systemui.action.CLEAR_MEMORY
  adb shell am kill-all
  adb shell cmd activity kill-all

  # Run any postponed dex‐opt jobs immediately
  adb shell cmd jobscheduler run -f android \
    "$(adb shell cmd jobscheduler list-jobs android \
      | grep background-dexopt | awk '{print $2}')"

  # Power management
  adb shell cmd power set-adaptive-power-saver-enabled true
  adb shell cmd power set-mode 0
  adb shell cmd power set-fixed-performance-mode-enabled false
  adb shell cmd power suppress-ambient-display true
  adb shell cmd power set-face-down-detector false
  adb shell settings put global enhanced_cpu_responsiveness 1
  adb shell settings put global sem_enhanced_cpu_responsiveness 1
  adb shell settings put global enhanced_processing 1
  adb shell settings put global omap.enhancement true

  vk_set(){
    adb shell setprop debug.renderengine.backend skiavk
    adb shell setprop debug.hwui.renderer skiavk
    adb shell setprop debug.hwui.use_vulkan true
  }
  gl_set(){
    adb shell setprop debug.renderengine.backend skiaglthreaded
    adb shell setprop debug.hwui.renderer skiagl
    adb shell setprop debug.hwui.use_vulkan false
  }
  vk_set

  adb shell settings put global storage.preload.complete 1
  adb shell settings put global background_gpu_usage 0
  adb shell settings put global enable_app_prefetch 1
  adb shell settings put global cached_apps_freezer enabled
  adb shell settings put global app_auto_restriction_enabled 1
  adb shell settings put global app_restriction_enabled true
  adb shell settings put global app_auto_restriction_enabled 1
  adb shell settings put global battery_saver_constants \ 
  "vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,fullbackup_deferred=true,keyvaluebackup_deferred=true, \
  gps_mode=low_power,data_saver=true,optional_sensors_disabled=true,advertiser_id_enabled=false"

  # Graphics
  adb shell device_config put graphics enable_cpu_boost true
  adb shell device_config put graphics enable_gpu_boost true

  # Driver
  adb shell settings put global game_low_latency_mode 1
  adb shell settings put global game_gpu_optimizing 1
  adb shell settings put global game_driver_mode 1
  adb shell settings put global game_driver_all_apps 1
  adb shell settings put global game_driver_opt_out_apps 1
  adb shell settings put global updatable_driver_all_apps 1
  adb shell settings put global updatable_driver_production_opt_out_apps 1
  adb shell settings put global angle_gl_driver_all_angle 1
  adb shell settings put global angle_debug_package com.android.angle
  adb shell settings put global angle_gl_driver_selection_values angle

  # Global settings
  adb shell settings put global updatable_driver_all_apps 1
  adb shell settings put global sqlite_compatibility_wal_flags "syncMode=OFF,fsyncMode=off"

  # Print data in .db files, clean:
  grep -vx -f <(sqlite3 Main.db .dump) <(sqlite3 "$DB" .schema)
  # Use below command fr update dg.db file:
  sqlite3 /data/data/com.google.android.gms/databases/dg.db "update main set c='0' where a like '%attest%';"

}

# Debug logging - only prints when DEBUG is set
log_debug(){
  [[ ${DEBUG:-0} -eq 1 ]] && printf '[DEBUG %s] %s\n' "$(date +%H:%M:%S)" "$*" || :
}

# Reset all configurations to default
reset_device_configs(){
  log "Resetting device configurations to default..."

  # List sections to reset
  local sections=(
    connectivity privacy runtime runtime_native runtime_native_boot
    systemui activity_manager package_manager_service window_manager
    wifi bluetooth adservices
  )

  # Reset each section
  for section in "${sections[@]}"; do
    adb shell cmd device_config reset "$section" >/dev/null 2>&1 || log "Failed to reset section: $section"
  done

  log "Device configurations reset successfully"
}

# Main function
main(){
  check_adb || exit 1

  # Parse command line arguments
  if [[ $# -gt 0 ]]; then
    case "$1" in
    apply) apply_device_configs ;;
    reset) reset_device_configs ;;
    *)
      echo "Usage: $0 [apply|reset]"
      exit 1
      ;;
    esac
  else
    # Default action
    apply_device_configs
  fi
}

# Execute main function if run directly
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
