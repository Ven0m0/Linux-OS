#!/usr/bin/env bash
# android-toolkit-config.sh - Apply optimized settings to Android devices
#
# Features:
# - Apply device_config settings for better performance/battery
# - Configure rendering, network, and battery optimizations
# - Set up ANGLE/Vulkan/WebView optimizations
# - Apply system-level tweaks
#
# Usage: ./android-toolkit-config.sh [OPTION]
#   -p, --profile NAME    Apply profile (performance|battery|balanced)
#   -i, --interactive     Show interactive menu (default if no args)
#   -c, --category NAME   Apply specific category of settings
#   -l, --list            List available categories
#   -d, --device ID       Target specific device (if multiple connected)
#   -y, --yes             Skip confirmations
#   -v, --verbose         Show detailed output
#   -h, --help            Show this help

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C

# --- Constants and globals ---
VERSION="1.0.0"
SCRIPT_NAME="${0##*/}"
ASSUME_YES=0
VERBOSE=0
DEVICE=""
PROFILE=""
CATEGORY=""

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper functions ---
log() {
  local level="$1"; shift
  case "$level" in
    info)  printf "${GREEN}[INFO]${NC} %s\n" "$*" ;;
    warn)  printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2 ;;
    error) printf "${RED}[ERROR]${NC} %s\n" "$*" >&2 ;;
    debug) [[ $VERBOSE -eq 1 ]] && printf "${BLUE}[DEBUG]${NC} %s\n" "$*" ;;
  esac
}

check_deps() {
  local missing=()
  for cmd in adb; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log error "Missing required dependencies: ${missing[*]}"
    if command -v pacman &>/dev/null; then
      log info "Install with: sudo pacman -S --needed android-tools"
    elif command -v apt &>/dev/null; then
      log info "Install with: sudo apt install -y android-tools-adb"
    elif command -v pkg &>/dev/null; then
      log info "Install with: pkg install android-tools"
    fi
    exit 1
  fi
}

check_adb_connection() {
  if ! adb get-state &>/dev/null; then
    log error "No device connected or unauthorized. Please connect a device and enable USB debugging."
    exit 1
  fi
  
  if [[ -n "$DEVICE" ]]; then
    # Use the specific device
    ADB_CMD=("adb" "-s" "$DEVICE")
    log debug "Using device: $DEVICE"
  else
    local devices
    mapfile -t devices < <(adb devices | grep -v "^List" | grep -v "^$" | cut -f1)
    
    if [[ ${#devices[@]} -eq 0 ]]; then
      log error "No devices connected"
      exit 1
    elif [[ ${#devices[@]} -gt 1 ]]; then
      log warn "Multiple devices found, using first device: ${devices[0]}"
      DEVICE="${devices[0]}"
      ADB_CMD=("adb" "-s" "$DEVICE")
    else
      DEVICE="${devices[0]}"
      ADB_CMD=("adb")
      log debug "Using device: $DEVICE"
    fi
  fi
}

run_adb() {
  local cmd=("${ADB_CMD[@]}" "$@")
  log debug "Running: ${cmd[*]}"
  if [[ $VERBOSE -eq 1 ]]; then
    "${cmd[@]}"
  else
    "${cmd[@]}" >/dev/null 2>&1 || {
      local rc=$?
      log error "Command failed: ${cmd[*]}"
      return $rc
    }
  fi
}

confirm() {
  if [[ $ASSUME_YES -eq 1 ]]; then
    return 0
  fi
  
  local prompt="$1"
  local default="${2:-n}"
  local yn="y/N"
  [[ $default == "y" ]] && yn="Y/n"
  
  read -r -p "$prompt [$yn] " answer
  answer=${answer:-$default}
  [[ ${answer,,} == "y"* ]]
}

# --- Configuration functions ---
apply_device_config() {
  local namespace="$1"
  local key="$2"
  local value="$3"
  log debug "Setting device_config $namespace/$key=$value"
  run_adb shell "cmd device_config put $namespace $key $value"
}

apply_system_setting() {
  local namespace="$1"
  local key="$2"
  local value="$3"
  log debug "Setting $namespace setting $key=$value"
  run_adb shell "settings put $namespace $key $value"
}

apply_prop() {
  local prop="$1"
  local value="$2"
  log debug "Setting prop $prop=$value"
  run_adb shell "setprop $prop $value"
}

apply_cmd() {
  local cmd="$1"
  shift
  log debug "Running cmd $cmd $*"
  run_adb shell "cmd $cmd $*"
}

# --- Configuration categories ---

config_connectivity() {
  log info "Applying connectivity optimizations..."
  
  apply_device_config connectivity dhcp_rapid_commit_enabled false
  apply_device_config netd_native parallel_lookup 0
  
  apply_system_setting global data_saver_mode 1
  apply_system_setting global multipath-tcp-enable 1
  apply_system_setting global ro.wifi.signal.optimized true
  apply_system_setting global mobile_data_always_on 0
  apply_system_setting global mobile_data_keepalive_enabled 0
  apply_system_setting global ble_scan_always_enabled 0
  apply_system_setting global wifi_scan_always_enabled 0
  apply_system_setting global wifi_watchdog_roaming 0
  apply_system_setting global network_scoring_ui_enabled 0
  apply_system_setting global network_avoid_bad_wifi 1
  apply_system_setting global wifi_suspend_optimizations_enabled 2
  apply_system_setting global wifi_stability 1
  
  apply_cmd netpolicy set restrict-background true
  apply_cmd wifi set-scan-always-available disabled
  apply_cmd wifi force-low-latency-mode enabled
  apply_cmd wifi force-hi-perf-mode enabled

  log info "Connectivity optimizations applied"
}

config_privacy() {
  log info "Applying privacy settings..."
  
  apply_device_config privacy bg_location_check_is_enabled true
  apply_device_config privacy safety_center_is_enabled true
  apply_device_config privacy location_accuracy_enabled true
  apply_device_config activity_manager set_sync_disabled_for_tests persistent
  
  apply_system_setting secure USAGE_METRICS_UPLOAD_ENABLED 0
  apply_system_setting secure usage_metrics_marketing_enabled 0
  apply_system_setting secure limit_ad_tracking 1
  apply_system_setting system send_security_reports 0
  apply_system_setting global package_usage_stats_enabled 0
  apply_system_setting global recent_usage_data_enabled 0
  apply_system_setting global show_non_market_apps_error 0
  apply_system_setting global app_usage_enabled 0
  apply_system_setting global media.metrics.enabled 0
  apply_system_setting global media.metrics 0
  apply_system_setting global webview_safe_browsing_enabled 0
  
  log info "Privacy settings applied"
}

config_battery() {
  log info "Applying battery optimizations..."
  
  local battery_constants="vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true"
  battery_constants+=",fullbackup_deferred=true,keyvaluebackup_deferred=true"
  battery_constants+=",gps_mode=low_power,data_saver=true,optional_sensors_disabled=true,advertiser_id_enabled=false"
  
  apply_system_setting global battery_saver_constants "$battery_constants"
  apply_system_setting global dynamic_power_savings_enabled 1
  apply_system_setting global adaptive_battery_management_enabled 0
  apply_system_setting global app_auto_restriction_enabled 1
  apply_system_setting global app_restriction_enabled true
  apply_system_setting global cached_apps_freezer enabled
  apply_system_setting global allow_heat_cooldown_always 1
  apply_system_setting global ram_expand_size_list 1
  apply_system_setting global native_memtag_sync 1
  apply_system_setting global background_gpu_usage 0
  apply_system_setting global enable_app_prefetch 1
  apply_system_setting global storage.preload.complete 1
  apply_system_setting global ota_disable_automatic_update 1
  apply_system_setting system background_power_saving_enable 1
  apply_system_setting system perf_profile performance
  apply_system_setting system intelligent_sleep_mode 0
  apply_system_setting system power_mode high
  
  apply_cmd power suppress-ambient-display true
  apply_cmd power set-face-down-detector false
  apply_cmd power set-fixed-performance-mode-enabled false
  apply_cmd power set-adaptive-power-saver-enabled true
  
  # Whitelist important system UI
  run_adb shell dumpsys deviceidle whitelist +com.android.systemui
  
  log info "Battery optimizations applied"
}

config_graphics() {
  log info "Applying graphics and rendering optimizations..."
  
  # GPU rendering and hardware acceleration
  apply_system_setting global force_gpu_rendering 1
  apply_system_setting global hardware_accelerated_rendering_enabled 1
  apply_system_setting global hardware_accelerated_graphics_decoding 1
  apply_system_setting global hardware_accelerated_video_decode 1
  apply_system_setting global hardware_accelerated_video_encode 1
  apply_system_setting global media.sf.hwaccel 1
  apply_system_setting global video.accelerate.hw 1
  apply_system_setting global ro.config.enable.hw_accel true
  apply_system_setting global debug.hwui.render_priority 1
  apply_system_setting global debug.hwui.use_disable_overdraw 1
  apply_system_setting global skia.force_gl_texture 1
  apply_system_setting global overlay_disable_force_hwc 1
  apply_system_setting global disable_hw_overlays 1
  apply_system_setting global gpu_rasterization_forced 1
  apply_system_setting global enable_lcd_text 1
  apply_system_setting global renderthread.skia.reduceopstasksplitting true
  apply_system_setting global hw2d.force 1
  apply_system_setting global hw3d.force 1
  apply_system_setting global multi_sampling_enabled 0
  apply_system_setting global sysui_font_cache_persist true

  # Device config settings
  apply_device_config graphics enable_cpu_boost true
  apply_device_config graphics enable_gpu_boost true
  apply_device_config graphics render_thread_priority high
  apply_device_config activity_manager force_high_refresh_rate true
  apply_device_config activity_manager enable_background_cpu_boost true
  apply_device_config surfaceflinger set_max_frame_rate_multiplier 0.5

  # SystemUI settings
  apply_device_config systemui window_cornerRadius 0
  apply_device_config systemui window_blur 0
  apply_device_config systemui window_shadow 0
  
  # Debug properties
  apply_prop debug.composition.type dyn
  apply_prop debug.fb.rgb565 0
  apply_prop debug.sf.disable_threaded_present false
  apply_prop debug.sf.predict_hwc_composition_strategy 1
  apply_prop debug.hwui.use_buffer_age true
  apply_prop debug.sf.gpu_comp_tiling 1
  apply_prop debug.enable.sglscale 1
  apply_prop debug.sdm.support_writeback 1
  apply_prop debug.sf.disable_client_composition_cache 0
  apply_prop debug.sf.use_phase_offsets_as_durations 1
  apply_prop debug.sf.enable_gl_backpressure 1
  apply_prop debug.sf.enable_advanced_sf_phase_offset 1
  apply_prop debug.egl.native_scaling 1
  apply_prop debug.egl.hw 1
  apply_prop debug.gl.hw 1
  apply_prop debug.sf.hw 1
  apply_prop debug.sf.no_hw_vsync 1
  apply_prop debug.sf.ddms 0
  apply_prop debug.sf.enable_hgl 1
  apply_prop debug.sf.enable_hwc_vds 1
  apply_prop debug.gfx.driver 1
  apply_prop debug.sf.perf_mode 1
  apply_prop debug.enabletr true
  apply_prop debug.qc.hardware true
  apply_prop debug.rs.reduce 1
  apply_prop debug.hwui.use_gpu_pixel_buffers false
  apply_prop debug.hwui.renderer_mode 1
  apply_prop debug.hwui.disabledither true
  apply_prop debug.hwui.enable_bp_cache true
  apply_prop debug.gralloc.map_fb_memory 1
  apply_prop debug.gralloc.enable_fb_ubwc 1
  apply_prop debug.gralloc.gfx_ubwc_disable 0
  apply_prop debug.gralloc.disable_hardware_buffer 1
  apply_prop debug.smart_scheduling 1
  apply_prop debug.hwui.disable_gpu_cache false
  apply_prop debug.gr.swapinterval 0
  apply_prop debug.egl.swapinterval 0
  apply_prop debug.slsi_platform 1
  apply_prop debug.sqlite.journalmode OFF
  apply_prop debug.sqlite.syncmode OFF
  apply_prop debug.sqlite.wal.syncmode ON
  apply_prop debug.stagefright.ccodec 1
  apply_prop debug.syncopts 3
  apply_prop debug.threadedOpt 1
  apply_prop debug.performance.tuning 1
  apply_prop debug.mdpcomp.enable 1
  apply_prop debug.tracing.mnc 0
  apply_prop debug.tracing.battery_status 0
  apply_prop debug.tracing.screen_state 0
  apply_prop debug.debuggerd.disable 1
  apply_prop debug.aw.power_scheduler_enable_idle_throttle 1
  apply_prop debug.aw.cpu_affinity_little 1
  apply_prop debug.sf.disable_backpressure 0

  # GUI optimizations
  run_adb shell wm set-sandbox-display-apis true
  run_adb shell wm disable-blur true
  run_adb shell wm scaling off
  run_adb shell cmd display dwb-logging-disable
  run_adb shell cmd display ab-logging-disable
  run_adb shell cmd looper_stats disable
  
  log info "Graphics optimizations applied"
}

config_webview() {
  log info "Configuring WebView and ANGLE..."
  
  # Configure WebView command line
  run_adb shell "echo 'webview --enable-features=DeferImplInvalidation,ScrollUpdateOptimizations' > /data/local/tmp/webview-command-line"
  run_adb shell "chmod 644 /data/local/tmp/webview-command-line"
  run_adb shell cmd webviewupdate set-webview-implementation com.android.webview.beta
  
  # Configure ANGLE
  apply_system_setting global angle_gl_driver_all_angle 1
  apply_system_setting global angle_debug_package com.android.angle
  apply_system_setting global angle_gl_driver_selection_values angle
  apply_system_setting global angle_gl_driver_selection_pkgs com.android.webview,com.android.webview.beta
  
  log info "WebView and ANGLE configured"
}

config_audio() {
  log info "Applying audio optimizations..."
  
  apply_system_setting global audio.deep_buffer.media true
  apply_system_setting global audio.parser.ip.buffer.size 0
  apply_system_setting global audio.offload.video true
  apply_system_setting global audio.offload.track.enable true
  apply_system_setting global audio.offload.passthrough false
  apply_system_setting global audio.offload.gapless.enabled true
  apply_system_setting global audio.offload.multiple.enabled true
  apply_system_setting global audio.offload.pcm.16bit.enable false
  apply_system_setting global audio.offload.pcm.24bit.enable false
  apply_system_setting global media.enable-commonsource true
  apply_system_setting global media.stagefright.thumbnail.prefer_hw_codecs true
  apply_system_setting global media.stagefright.use-awesome true
  apply_system_setting global media.stagefright.enable-record false
  apply_system_setting global media.stagefright.enable-scan false
  apply_system_setting global media.stagefright.enable-meta true
  apply_system_setting global media.stagefright.enable-http true
  apply_prop debug.media.video.frc false
  apply_prop debug.media.video.vpp false
  
  # Additional audio settings
  apply_system_setting system tube_amp_effect 1
  apply_system_setting system k2hd_effect 1
  
  log info "Audio optimizations applied"
}

config_input() {
  log info "Optimizing input settings..."
  
  # Touch and input settings
  apply_system_setting global touch_calibration 1
  apply_system_setting global touch.size.bias 0
  apply_system_setting global touch.size.isSummed 0
  apply_system_setting global touch.size.scale 1
  apply_system_setting global touch.pressure.scale 0.1
  apply_system_setting global touch.distance.scale 0
  apply_system_setting secure touch_blocking_period 0.0
  apply_system_setting secure tap_duration_threshold 0.0
  apply_system_setting secure long_press_timeout 250
  apply_system_setting secure multi_press_timeout 250
  apply_system_setting global window_focus_timeout 250
  
  # Animation settings (disable/minimize)
  apply_system_setting global animator_duration_scale 0.0
  apply_system_setting global transition_animation_scale 0.0
  apply_system_setting global window_animation_scale 0.0
  apply_system_setting system slider_animation_duration 0.0
  apply_system_setting system remove_animations 1
  apply_system_setting system reduce_animations 1
  apply_system_setting secure user_wait_timeout 0
  apply_system_setting global view.scroll_friction 0
  apply_system_setting global reduce_transitions 1
  apply_system_setting global shadow_animation_scale 0
  apply_system_setting global render_shadows_in_compositor false
  apply_system_setting global remove_animations 1
  apply_system_setting global fancy_ime_animations 0
  
  # Rotation settings
  apply_system_setting system accelerometer_rotation 0
  
  # Sensor settings
  apply_system_setting secure sensors_off 1
  apply_system_setting secure sensors_off_enabled 1
  apply_system_setting secure sensor_privacy 1
  apply_system_setting secure skip_gesture 0
  apply_system_setting secure silence_gesture 0
  apply_system_setting secure screensaver_enabled 0
  apply_system_setting secure reduce_bright_colors_activated 1
  apply_system_setting global accessibility_reduce_transparency 1
  apply_system_setting system motion_engine 0
  apply_system_setting system master_motion 0
  
  log info "Input optimizations applied"
}

config_system() {
  log info "Applying system optimizations..."
  
  # Runtime and package settings
  apply_device_config runtime force_disable_pr_dexopt false
  apply_device_config runtime_native metrics.write-to-statsd true
  apply_device_config runtime_native use_app_image_startup_cache true
  apply_device_config runtime_native_boot use_generational_gc true
  apply_device_config runtime_native_boot iorap_readahead_enable false
  apply_device_config activity_manager use_compaction true
  apply_device_config package_manager_service Archiving__enable_archiving false
  apply_device_config runtime_native_boot pin_camera false
  apply_device_config launcher ENABLE_QUICK_LAUNCH_V2 true
  apply_device_config launcher enable_quick_launch_v2 true
  apply_device_config privacy location_access_check_enabled false
  apply_device_config privacy location_accuracy_enabled false
  apply_device_config privacy safety_protection_enabled true
  
  # System settings
  apply_system_setting system bluetooth_discoverability 1
  apply_system_setting system multicore_packet_scheduler 1
  
  # Game/Driver settings
  apply_system_setting global game_low_latency_mode 1
  apply_system_setting global game_gpu_optimizing 1
  apply_system_setting global game_driver_mode 1
  apply_system_setting global game_driver_all_apps 1
  apply_system_setting global game_driver_opt_out_apps 1
  apply_system_setting global updatable_driver_all_apps 1
  apply_system_setting global updatable_driver_production_opt_out_apps 1
  apply_system_setting global enhanced_processing 2
  apply_system_setting global enhanced_cpu_responsiveness 1
  apply_system_setting global sem_enhanced_cpu_responsiveness 1
  apply_system_setting global restricted_device_performance 1,0
  apply_system_setting global omap.enhancement true
  
  # Log settings
  run_adb shell logcat -G 128K -b main -b system
  run_adb shell logcat -G 64K -b radio -b events -b crash
  run_adb shell cmd display ab-logging-disable
  run_adb shell cmd display dwb-logging-disable
  run_adb shell cmd looper_stats disable
  run_adb shell dumpsys power set_sampling_rate 0
  
  # Apply sqlite optimizations
  apply_system_setting global sqlite_compatibility_wal_flags "syncMode=OFF,fsyncMode=off"
  
  # Dark mode
  run_adb shell cmd uimode night yes
  run_adb shell cmd uimode car no
  
  # App foreground management
  run_adb shell cmd appops set com.google.android.gms START_FOREGROUND ignore
  run_adb shell cmd appops set com.google.android.gms INSTANT_APP_START_FOREGROUND ignore
  run_adb shell cmd appops set com.google.android.ims START_FOREGROUND ignore
  run_adb shell cmd appops set com.google.android.ims INSTANT_APP_START_FOREGROUND ignore
  
  # Doze settings
  run_adb shell cmd deviceidle force-idle
  run_adb shell cmd deviceidle unforce
  run_adb shell dumpsys deviceidle whitelist +com.android.systemui
  
  log info "System optimizations applied"
}

config_doze() {
  log info "Optimizing doze and app standby..."
  
  # Doze management commands
  run_adb shell cmd deviceidle force-idle
  run_adb shell cmd deviceidle unforce
  run_adb shell dumpsys deviceidle whitelist +com.android.systemui
  
  # App standby settings
  apply_device_config activity_manager bg_current_drain_auto_restrict_abusive_apps_enabled false
  
  log info "Doze and app standby optimized"
}

optimize_art() {
  log info "Optimizing Android Runtime (ART)..."
  
  # Enable background dexopt job
  run_adb shell pm bg-dexopt-job --enable
  
  # Force jobs to run immediately
  local job_id
  job_id=$(run_adb shell cmd jobscheduler list-jobs android | grep -i "background-dexopt" | awk '{print $2}')
  if [[ -n "$job_id" ]]; then
    run_adb shell cmd jobscheduler run -f android "$job_id"
  fi
  
  # Compile packages with speed-profile and speed
  run_adb shell cmd package compile -af --full --secondary-dex -m speed-profile
  run_adb shell cmd package compile -a -f --full --secondary-dex -m speed
  run_adb shell pm art dexopt-packages -r bg-dexopt
  
  log info "ART optimization complete"
}

apply_profile() {
  local profile="$1"
  
  log info "Applying profile: $profile"
  
  # Apply base optimizations for all profiles
  config_system
  config_webview
  optimize_art
  
  case "$profile" in
    performance)
      config_graphics
      config_input
      apply_system_setting global animator_duration_scale 0.0
      apply_system_setting global transition_animation_scale 0.0
      apply_system_setting global window_animation_scale 0.0
      apply_cmd thermalservice override-status 1
      log info "Performance profile applied"
      ;;
    battery)
      config_battery
      config_doze
      config_privacy
      apply_system_setting global animator_duration_scale 0.5
      apply_system_setting global transition_animation_scale 0.5
      apply_system_setting global window_animation_scale 0.5
      log info "Battery profile applied"
      ;;
    balanced|*)
      config_graphics
      config_battery
      apply_system_setting global animator_duration_scale 0.3
      apply_system_setting global transition_animation_scale 0.3
      apply_system_setting global window_animation_scale 0.3
      log info "Balanced profile applied"
      ;;
  esac
}

# --- Main functionality ---

# Print usage information
usage() {
  cat <<EOF
${CYAN}Android Toolkit: Config Optimizer v${VERSION}${NC}

${YELLOW}Usage:${NC} $SCRIPT_NAME [OPTIONS]

${YELLOW}Options:${NC}
  -p, --profile NAME    Apply profile (performance|battery|balanced)
  -i, --interactive     Show interactive menu (default if no args)
  -c, --category NAME   Apply specific category of settings
  -l, --list            List available categories
  -d, --device ID       Target specific device (if multiple connected)
  -y, --yes             Skip confirmations
  -v, --verbose         Show detailed output
  -h, --help            Show this help

${YELLOW}Categories:${NC}
  connectivity  - Network, WiFi, and connectivity settings
  graphics      - Rendering and display settings
  battery       - Battery and power optimization
  audio         - Audio processing settings
  input         - Input, animation, and gesture settings
  webview       - Browser and WebView settings
  system        - General system optimization
  doze          - App standby and doze settings
  art           - Runtime and dex optimization
  privacy       - Privacy-focused settings
  all           - Apply all optimizations

${YELLOW}Examples:${NC}
  $SCRIPT_NAME --profile performance
  $SCRIPT_NAME -c graphics -c battery -y
  $SCRIPT_NAME -i
EOF
}

list_categories() {
  cat <<EOF
Available categories:
- connectivity: Network, WiFi, and connectivity settings
- graphics: Rendering and display settings
- battery: Battery and power optimization
- audio: Audio processing settings
- input: Input, animation, and gesture settings
- webview: Browser and WebView settings
- system: General system optimization
- doze: App standby and doze settings
- art: Runtime and dex optimization
- privacy: Privacy-focused settings
- all: Apply all optimizations
EOF
}

apply_category() {
  local category="$1"
  
  case "$category" in
    connectivity) config_connectivity ;;
    graphics) config_graphics ;;
    battery) config_battery ;;
    audio) config_audio ;;
    input) config_input ;;
    webview) config_webview ;;
    system) config_system ;;
    doze) config_doze ;;
    art) optimize_art ;;
    privacy) config_privacy ;;
    all)
      config_connectivity
      config_graphics
      config_battery
      config_audio
      config_input
      config_webview
      config_system
      config_doze
      optimize_art
      config_privacy
      ;;
    *)
      log error "Unknown category: $category"
      list_categories
      return 1
      ;;
  esac
}

show_interactive_menu() {
  # Check terminal capabilities
  if [[ ! -t 1 ]]; then
    log error "Interactive menu requires a terminal"
    exit 1
  fi
  
  # Try to use dialog if available, otherwise use plain read
  if command -v dialog &>/dev/null; then
    use_dialog_menu
  else
    use_plain_menu
  fi
}

use_dialog_menu() {
  local choice
  
  while true; do
    choice=$(dialog --clear --backtitle "Android Toolkit: Config Optimizer v${VERSION}" \
      --title "Main Menu" --menu "Select an action:" 20 60 12 \
      "1" "Apply performance profile" \
      "2" "Apply battery profile" \
      "3" "Apply balanced profile" \
      "4" "Custom category configuration" \
      "5" "Apply all optimizations" \
      "6" "Show device info" \
      "q" "Quit" \
      3>&1 1>&2 2>&3)
    
    clear
    
    case "$choice" in
      1) apply_profile "performance" ;;
      2) apply_profile "battery" ;;
      3) apply_profile "balanced" ;;
      4)
        local cat_choice
        cat_choice=$(dialog --clear --backtitle "Android Toolkit: Config Optimizer v${VERSION}" \
          --title "Category Selection" --checklist "Select categories to apply:" 20 60 10 \
          "connectivity" "Network settings" OFF \
          "graphics" "Rendering settings" OFF \
          "battery" "Power optimization" OFF \
          "audio" "Audio settings" OFF \
          "input" "Input and animation" OFF \
          "webview" "Browser settings" OFF \
          "system" "System optimization" OFF \
          "doze" "App standby" OFF \
          "art" "Runtime optimization" OFF \
          "privacy" "Privacy settings" OFF \
          3>&1 1>&2 2>&3)
        
        clear
        
        if [[ -n "$cat_choice" ]]; then
          for cat in $cat_choice; do
            cat="${cat//\"/}"  # Remove quotes
            apply_category "$cat"
          done
        fi
        ;;
      5) apply_category "all" ;;
      6) 
        run_adb shell getprop ro.build.version.release > /tmp/device_info.txt
        run_adb shell getprop ro.product.model >> /tmp/device_info.txt
        run_adb shell dumpsys battery | grep level >> /tmp/device_info.txt
        dialog --title "Device Info" --textbox /tmp/device_info.txt 20 60
        ;;
      q|"") break ;;
    esac
  done
}

use_plain_menu() {
  local choice
  
  while true; do
    echo -e "${CYAN}=== Android Toolkit: Config Optimizer v${VERSION} ===${NC}"
    echo -e "${YELLOW}1)${NC} Apply performance profile"
    echo -e "${YELLOW}2)${NC} Apply battery profile"
    echo -e "${YELLOW}3)${NC} Apply balanced profile"
    echo -e "${YELLOW}4)${NC} Custom category configuration"
    echo -e "${YELLOW}5)${NC} Apply all optimizations"
    echo -e "${YELLOW}6)${NC} Show device info"
    echo -e "${YELLOW}q)${NC} Quit"
    echo
    read -r -p "Select an option: " choice
    
    case "$choice" in
      1) apply_profile "performance" ;;
      2) apply_profile "battery" ;;
      3) apply_profile "balanced" ;;
      4)
        echo -e "${CYAN}Available categories:${NC}"
        echo "connectivity, graphics, battery, audio, input, webview, system, doze, art, privacy"
        read -r -p "Enter categories separated by space: " categories
        for cat in $categories; do
          apply_category "$cat"
        done
        ;;
      5) apply_category "all" ;;
      6)
        echo -e "${CYAN}=== Device Info ===${NC}"
        run_adb shell getprop ro.build.version.release
        run_adb shell getprop ro.product.model
        run_adb shell dumpsys battery | grep level
        echo
        read -r -p "Press Enter to continue..."
        ;;
      q|Q) break ;;
      *) echo -e "${RED}Invalid option${NC}" ;;
    esac
    
    echo
  done
}

# --- Parse arguments ---
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--profile)
        PROFILE="$2"
        shift 2
        ;;
      -i|--interactive)
        INTERACTIVE=1
        shift
        ;;
      -c|--category)
        CATEGORIES+=("$2")
        shift 2
        ;;
      -l|--list)
        list_categories
        exit 0
        ;;
      -d|--device)
        DEVICE="$2"
        shift 2
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  # Check dependencies
  check_deps
  
  # Parse command-line arguments
  local INTERACTIVE=0
  local -a CATEGORIES=()
  parse_args "$@"
  
  # Verify ADB connection
  check_adb_connection
  
  # If no specific action was provided, use interactive mode
  if [[ -z "$PROFILE" && ${#CATEGORIES[@]} -eq 0 && $INTERACTIVE -eq 0 ]]; then
    INTERACTIVE=1
  fi
  
  # Execute based on provided arguments
  if [[ -n "$PROFILE" ]]; then
    apply_profile "$PROFILE"
  fi
  
  if [[ ${#CATEGORIES[@]} -gt 0 ]]; then
    for category in "${CATEGORIES[@]}"; do
      apply_category "$category"
    done
  fi
  
  if [[ $INTERACTIVE -eq 1 ]]; then
    show_interactive_menu
  fi
  
  log info "Optimizations complete"
}

main "$@"
