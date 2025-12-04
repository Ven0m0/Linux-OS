 #!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
IFS=$'\n\t'
export LC_ALL=C LANG=C
# === Color Palette (Trans Flag) ===
if [[ -t 1 ]]; then
  readonly BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
  readonly BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
  readonly LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
  readonly DEF=$'\e[0m' BLD=$'\e[1m' UND=$'\e[4m'
else
  readonly BLK="" RED="" GRN="" YLW="" BLU="" MGN="" CYN="" WHT=""
  readonly LBLU="" PNK="" BWHT="" DEF="" BLD="" UND=""
fi
# === Logging Functions ===
xecho(){ printf '%b\n' "$*"; }
log(){ xecho "${BLU}${BLD}[*]${DEF} $*"; }
msg(){ xecho "${GRN}${BLD}[+]${DEF} $*"; }
warn(){ xecho "${YLW}${BLD}[!]${DEF} $*" >&2; }
err(){ xecho "${RED}${BLD}[-]${DEF} $*" >&2; }
die(){ err "$1"; exit "${2:-1}"; }
dbg(){ [[ ${DEBUG:-0} -eq 1 ]] && xecho "${MGN}[DBG]${DEF} $*" || :; }
sec(){ printf '\n%s%s=== %s ===%s\n' "$CYN" "$BLD" "$*" "$DEF"; }
# === Tool Detection ===
has(){ command -v "$1" &>/dev/null; }

hasname(){
  local cmd
  for cmd in "$@"; do
    if has "$cmd"; then
      printf '%s' "$cmd"
      return 0
    fi
  done
  return 1
}

# === Environment Detection ===
readonly IS_TERMUX="$([[ -d /data/data/com.termux/files ]] && echo 1 || echo 0)"
readonly NPROC="$(nproc 2>/dev/null || echo 4)"

# === ADB/Device Utilities ===
detect_adb(){
  local adb_cmd
  if ((IS_TERMUX)); then
    adb_cmd="$(hasname rish)" || {
      warn "rish not found; install Shizuku for device access"
      return 1
    }
  else
    adb_cmd="$(hasname adb)" || {
      err "adb not found; install Android SDK platform-tools"
      return 1
    }
  fi
  printf '%s' "$adb_cmd"
}

ash(){
  local adb_cmd
  adb_cmd="${ADB_CMD:-$(detect_adb)}" || return 1

  if ((IS_TERMUX)); then
    if [[ $# -eq 0 ]]; then
      "$adb_cmd" sh
    else
      "$adb_cmd" "$@" 2>/dev/null || return 1
    fi
  else
    if [[ $# -eq 0 ]]; then
      "$adb_cmd" shell
    else
      "$adb_cmd" shell "$@" 2>/dev/null || return 1
    fi
  fi
}

device_ok(){
  local adb_cmd
  adb_cmd="${ADB_CMD:-$(detect_adb)}" || return 1
  if ((IS_TERMUX)); then
    [[ -n $adb_cmd ]] || { err "rish not available; install Shizuku"; return 1; }
    return 0
  fi
  "$adb_cmd" start-server &>/dev/null || :
  "$adb_cmd" get-state &>/dev/null || { err "No device connected; enable USB debugging"; return 1; }
  return 0
}

wait_for_device(){
  local timeout="${1:-30}"
  local adb_cmd
  adb_cmd="${ADB_CMD:-$(detect_adb)}" || return 1
  if ((IS_TERMUX)); then
    return 0
  fi
  log "Waiting for device (timeout: ${timeout}s)..."
  timeout "$timeout" "$adb_cmd" wait-for-device || {
    err "Device connection timeout"
    return 1
  }
  msg "Device connected"
}

# === Confirmation Prompt ===
confirm(){
  local prompt="${1:-Continue? }"
  local reply

  while :; do
    read -rp "$prompt [y/N] " reply
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no|"") return 1 ;;
      *) warn "Please answer y or n" ;;
    esac
  done
}

# === Find Tools with Fallbacks ===
FD="${FD:-$(hasname fd fdfind || :)}"
RG="${RG:-$(hasname rg grep || :)}"
BAT="${BAT:-$(hasname bat batcat cat || :)}"
SD="${SD:-$(hasname sd || :)}"
readonly FD RG BAT SD

# Detect and cache ADB command
ADB_CMD="$(detect_adb || :)"
export ADB_CMD

# https://github.com/YurinDoctrine/adbloat
# WARNING: These tweaks are extremely aggressive and may cause instability. 
# For a safer, optimized subset, use: ./android-optimize.sh experimental

start(){
  sec "Aggressive Cleanup (on-device)"
  warn "This will uninstall 3rd-party apps and clear system app data"
  confirm "Proceed with aggressive cleanup?" || return 0

  log "Running cleanup (this combines 1000+ commands into 1 ADB call)..."
  
  local adb_cmd
  adb_cmd="${ADB_CMD:-$(detect_adb)}"
  
  # Run loops directly on device to avoid ADB latency overhead (1 call vs 1000+)
  "$adb_cmd" shell << 'CLEANUP_EOF' && msg "Cleanup complete" || err "Cleanup failed"
for pkg in $(pm list packages -3 | cut -d: -f2); do 
  pm uninstall -k --user 0 "$pkg" 2>/dev/null || true
done
for pkg in $(pm list packages -s | cut -d: -f2); do 
  pm clear --user 0 "$pkg" 2>/dev/null || true
done
for pkg in $(pm list packages | cut -d: -f2); do 
  pm reset-permissions -p "$pkg" 2>/dev/null || true
done
pm uninstall --user 0 com.google.android.googlequicksearchbox 2>/dev/null || true
CLEANUP_EOF
}

tweaks(){
  sec "Applying Experimental Tweaks"
  log "Batching 1100+ commands into 1 ADB call for massive performance improvement..."

  local adb_cmd
  adb_cmd="${ADB_CMD:-$(detect_adb)}"

  # Batch all adb shell commands for massive performance improvement
  # This reduces 1100+ separate ADB connections to just 1
  "$adb_cmd" shell << 'TWEAKS_EOF' && msg "Tweaks applied successfully" || {
    err "Some tweaks may have failed (this is normal on some devices)"
    return 1
  }
device_config put runtime_native_boot pin_camera false
device_config put launcher ENABLE_QUICK_LAUNCH_V2 true
device_config put launcher enable_quick_launch_v2 true
device_config put privacy location_access_check_enabled false
device_config put privacy location_accuracy_enabled false
device_config put privacy safety_protection_enabled true
device_config put activity_manager use_compaction true
device_config put activity_manager set_sync_disabled_for_tests persistent
device_config put activity_manager enable_background_cpu_boost true
device_config put activity_manager force_high_refresh_rate true
device_config put graphics render_thread_priority high
device_config put graphics enable_gpu_boost true
device_config put graphics enable_cpu_boost true
device_config put surfaceflinger set_max_frame_rate_multiplier 0.5
device_config put systemui window_cornerRadius 0
device_config put systemui window_blur 0
device_config put systemui window_shadow 0
dumpsys deviceidle whitelist +com.android.systemui
dumpsys power set_sampling_rate 0
cmd shortcut reset-all-throttling
cmd power set-fixed-performance-mode-enabled true
cmd power set-adaptive-power-saver-enabled false
cmd power set-mode 0
cmd netpolicy set restrict-background true
cmd appops set com.google.android.gms START_FOREGROUND ignore
cmd appops set com.google. android.gms INSTANT_APP_START_FOREGROUND ignore
cmd appops set com.google.android. ims START_FOREGROUND ignore
cmd appops set com.google.android.ims INSTANT_APP_START_FOREGROUND ignore
cmd activity idle-maintenance
cmd thermalservice override-status 1
cmd looper_stats disable
cmd display ab-logging-disable
cmd display dwb-logging-disable
pm trim-caches 999999M
pm compile -a -f --check-prof false -m speed
pm compile -a -f --secondary-dex --check-prof false -m speed
pm compile -a -f --check-prof false --compile-layouts
pm trim-caches 999999M
wipe cache
recovery --wipe_cache
rm -rf /cache/*. apk
rm -rf /cache/*.tmp
rm -rf /cache/*.log
rm -rf /data/log/*
rm -rf /data/*. log
rm -rf /data/mlog/*
rm -rf /data/klog/*
rm -rf /data/ap-log/*
rm -rf /data/cp-log/*
rm -rf /data/last_alog
rm -rf /data/last_kmsg
rm -rf /data/dontpanic/*
rm -rf /data/memorydump/*
rm -rf /data/dumplog/*
rm -rf /data/rdr/*
rm -rf /data/adb/*
rm -rf /data/tombstones/*
rm -rf /data/backup/pending/*
rm -rf /data/system/dropbox/*
rm -rf /data/system/usagestats/*
rm -rf /data/anr/*
rm -rf /data/crashdata/*
rm -rf /data/dalvik-cache/*
rm -rf /data/data/*/cache/*
rm -rf /data/cache/*.*
rm -rf /data/resource-cache/*
rm -rf /data/local/*
rm -rf /data/clipboard/*
rm -rf /dev/log/main/*
rm -rf /sdcard/log/*
rm -rf /sdcard/LogService/*
rm -rf /storage/sdcard0/LogService/*
rm -rf /storage/sdcard1/LogService/*
rm -rf /storage/sdcard0/LOST. DIR/*
rm -rf /storage/sdcard1/LOST.DIR/*
pm trim-caches 999999M
sm fstrim
logcat -P ""
logcat -c
setprop persist.log.tag S
wm scaling off
wm disable-blur true
wm set-sandbox-display-apis true
settings put global DEVICE_PROVISIONED 1
settings put global ro.revision 0
settings put global ro.rom.zone 2
settings put global ro.config. rom_lite_old_features true
settings put global ro.setupwizard.enterprise_mode 1
settings put global ro. fps_enable 1
settings put global ro.fps. capsmin 60
settings put global debug.fps. render. fast 1
settings put global dont. lower.fps true
settings put global stabilizer.fps true
settings put global stable.fps. enable true
settings put global ro.vendor.display.touch.idle. enable true
settings put global persist.vendor.disable_idle_fps true
settings put global vendor.display.enable_default_color_mode 1
settings put global vendor.display.disable_scaler 0
settings put global vendor.display. disable_excl_rect 0
settings put global vendor. display.disable_excl_rect_partial_fb 1
settings put global vendor.display. enable_async_powermode 1
settings put global vendor. display.disable_inline_rotator 1
settings put global vendor.display. disable_ext_anim 1
settings put global vendor.display.idle_time 0
settings put global vendor.display. idle_time_inactive 0
settings put global vendor. display.enhance_idle_time 1
settings put global vendor.display.enable_optimize_refresh 1
settings put global vendor. display.disable_metadata_dynamic_fps 1
settings put global vendor.display. use_smooth_motion 1
settings put global vendor. display.enable_camera_smooth 1
settings put global camera.disable_zsl_mode 1
settings put global debug.refresh_rate. view_override 1
settings put global debug. threadedOpt 1
settings put secure thread_priority highest HIGHEST
settings put secure support_highfps 1
settings put secure refresh_rate_mode 2
settings put secure user_wait_timeout 0
settings put system thermal_limit_refresh_rate 0
settings put system min_frame_rate 60. 0
settings put system min_refresh_rate 60.0
settings put system display_color_mode 0
settings put system remove_animations 1
settings put system reduce_animations 1
settings put system slider_animation_duration 250
settings put global window_animation_scale 0.25
settings put global transition_animation_scale 0.25
settings put global animator_duration_scale 0.0
settings put global remove_animations 1
settings put global fancy_ime_animations 0
settings put global visual_bars false
settings put global reduce_transitions 1
settings put global shadow_animation_scale 0
settings put global render_shadows_in_compositor false
settings put global window_focus_timeout 250
settings put global persist.sys.rotationanimation false
settings put global sys.rotation. animscale 0.25
settings put global sys.disable_ext_animation 1
settings put global sys.enable_grip_rejection 1
settings put global sys. refresh. dirty 0
settings put global view. touch_slop 1
settings put global view.scroll_friction 0
settings put global view.fading_edge_length 1
settings put global persist.touch_vsync_opt 1
settings put global persist.touch_move_opt 1
settings put global touch_calibration 1
settings put global touch. size.bias 0
settings put global touch.size.isSummed 0
settings put global touch. size.scale 1
settings put global touch. pressure.scale 0. 1
settings put global touch.distance.scale 0
settings put secure touch_blocking_period 0. 0
settings put secure tap_duration_threshold 0.0
settings put secure long_press_timeout 250
settings put secure multi_press_timeout 250
settings put secure speed_mode_enable 1
settings put system speed_mode 1
settings put global speed_mode_on 1
settings put global enable_hardware_acceleration 1
settings put global hardware_accelerated_rendering_enabled 1
settings put global hardware_accelerated_graphics_decoding 1
settings put global hardware_accelerated_video_decode 1
settings put global hardware_accelerated_video_encode 1
settings put global media.sf.hwaccel 1
settings put global video.accelerate. hw 1
settings put global hwui.private_hal_readback 1
settings put global debug.hwui.render_priority 1
settings put global debug.hwui.use_partial_updates false
settings put global debug.hwui.show_layers_updates false
settings put global debug.hwui.show_layer_grid 0
settings put global debug.hwui.show_layer_bounds 0
settings put global debug. hwui.overdraw false
settings put global debug.hwui.profile false
settings put global debug.hwui.use_d2d 1
settings put global debug.hwui.use_hint_manager false
settings put global ro.vendor.hwui.platform 1
settings put global persist.texture_cache_opt 1
settings put global disable_hw_overlays 1
settings put global overlay_disable_force_hwc 1
settings put global renderthread.skia. reduceopstasksplitting true
settings put global skia.force_gl_texture 1
settings put global omap.enhancement true
settings put global ENFORCE_PROCESS_LIMIT false
settings put global restricted_device_performance 1,0
settings put global sem_enhanced_cpu_responsiveness 1
settings put global enhanced_cpu_responsiveness 1
settings put global enhanced_processing 2
settings put global debug.multicore. processing 1
settings put global GPUTURBO_SWITCH 1
settings put global GPUTUNER_SWITCH 1
settings put global zen_mode 2
settings put global game_low_latency_mode 1
settings put global game_gpu_optimizing 1
settings put global game_driver_mode 1
settings put global game_driver_all_apps 1
settings put global game_driver_opt_out_apps 1
settings put global updatable_driver_all_apps 1
settings put global updatable_driver_production_opt_out_apps 1
settings put global network_avoid_bad_wifi 1
settings put global network_scoring_ui_enabled 0
settings put global wifi_watchdog_roaming 0
settings put global wifi. supplicant_scan_interval 300
settings put global wifi_scan_always_enabled 0
settings put global ble_scan_always_enabled 0
settings put global hotword_detection_enabled 0
settings put global mobile_data_always_on 0
settings put global mobile_data_keepalive_enabled 0
settings put global background_data 0
settings put global data_roaming_settings 0
settings put global data_roaming_int 0
settings put global data_roaming 0
settings put global data_saver_mode 1
settings put global lte_category 4
settings put global top_app_dexopt_with_speed_profile true
settings put global tombstoned. max_tombstone_count 20
settings put global vnswap. enabled false
settings put global cgroup_disable memory
settings put global sys_traced 0
settings put global wifi_verbose_logging_enabled 0
settings put global send_action_app_error 0
settings put global send_action_app_error_native 0
settings put global foreground_service_starts_logging_enabled 0
settings put global enable_diskstats_logging 0
settings put global activity_starts_logging_enabled 0
settings put global profiler. force_disable_err_rpt 1
settings put global profiler.force_disable_ulog 1
settings put global profiler.debugmonitor false
settings put global profiler.launch false
settings put global logcat. live disable
settings put global config.disable_consumerir true
settings put global logd.kernel false
settings put global vendor.display.disable_hw_recovery_dump 1
settings put global profiler.hung. dumpdobugreport false
settings put global trustkernel. log.state disable
settings put global persist.sample. eyetracking. log 0
settings put global media.metrics.enabled 0
settings put global media.metrics 0
settings put global logd.logpersistd. enable false
settings put global logd.statistics 0
settings put global config.stats 0
settings put global debug.enable. wl_log 0
settings put global debug.als.logs 0
settings put global debug. svi.logs 0
settings put global show_non_market_apps_error 0
settings put global app_usage_enabled 0
settings put global package_usage_stats_enabled 0
settings put global recent_usage_data_enabled 0
settings put global persist.service.debuggable 0
settings put global persist.logd.limit off
settings put global persist.logd.size 0
settings put global persist. bt. iot.enablelogging false
settings put global vendor.bluetooth.startbtlogger false
settings put global ro.vendor.connsys.dedicated. log 0
settings put global ro.hw_disable_instantonline true
settings put global sys.wifitracing. started 0
settings put global sys. deepdiagnose.support 0
settings put system status_logging_cnt 0
settings put system anr_debugging_mechanism 0
settings put system anr_debugging_mechanism_status 0
settings put system send_security_reports 0
settings put system remote_control 0
settings put system dk_log_level 0
settings put system user_log_enabled 0
settings put system window_orientation_listener_log 0
settings put system rakuten_denwa 0
settings put system mcf_continuity 0
settings put system mcf_continuity_permission_denied 1
settings put system mcf_permission_denied 1
settings put system multicore_packet_scheduler 1
settings put secure limit_ad_tracking 1
settings put secure usage_metrics_marketing_enabled 0
settings put secure USAGE_METRICS_UPLOAD_ENABLED 0
settings put secure upload_debug_log_pref 0
settings put secure upload_log_pref 0
settings put secure location_providers_allowed -network
settings put secure adaptive_connectivity_enabled 0
settings put secure ssl_session_cache null
settings put global multipath-tcp-enable 1
settings put global sys.net.support. netprio true
settings put global dns_resolvability_required 0
settings put global net.dns1 194.242.2.9
settings put global net.dns2 194.242.2.9
settings put global webview_safe_browsing_enabled 0
settings put global wifi_mac_randomization 2
settings put global wifi_connected_mac_randomization_supported 2
settings put global wifi_safe_mode 1
settings put global wifi_stability 1
settings put global wifi_suspend_optimizations_enabled 2
settings put global persist.mm.sta.enable 0
settings put global ro.data.large_tcp_window_size true
settings put global persist.data.tcp_rst_drop true
settings put global ro.config.hw_new_wifitopdp 1
settings put global ro.config.hw_wifipro_enable true
settings put global ro.config. wifi_fast_bss_enable true
settings put global config.disable_rtt true
settings put global ro.config.hw_privacymode true
settings put global ro.config.hw_perfhub true
settings put global ro.config. hw_perfgenius true
settings put global ro.config.enable_perfhub_fling true
settings put global persist.perf. level 2
settings put global vidc.debug.perf. mode 2
settings put global vidc.debug.level 0
settings put global libc.debug.malloc 0
settings put global debug.syncopts 3
settings put global debug.hwc.logvsync 0
settings put global debug. hwc.nodirtyregion 1
settings put global debug.hwc.force_gpu 1
settings put global debug.hwc.force_gpu_vsync 1
settings put global debug.hwc.fakevsync 1
settings put global debug.hwc.otf 1
settings put global debug.hwc.winupdate 1
settings put global debug.hwc.disabletonemapping true
settings put global debug.hwui.use_buffer_age false
settings put global persist.alloc_buffer_sync true
settings put global CPU_MIN_CHECK_DURATION false
settings put global MIN_CRASH_INTERVAL false
settings put global GC_MIN_INTERVAL false
settings put global GC_TIMEOUT false
settings put global SERVICE_TIMEOUT false
settings put global PROC_START_TIMEOUT false
settings put global MAX_PROCESSES false
settings put global MAX_ACTIVITIES false
settings put global MAX_SERVICE_INACTIVITY false
settings put global MIN_RECENT_TASKS false
settings put global MAX_RECENT_TASKS false
settings put global ACTIVITY_INACTIVITY_RESET_TIME false
settings put global APP_SWITCH_DELAY_TIME false
settings put global CONTENT_APP_IDLE_OFFSET false
settings put global foreground_mem_priority high
settings put global ro. FOREGROUND_APP_ADJ 0
settings put global ro.HOME_APP_ADJ 1
settings put global ro.VISIBLE_APP_ADJ 2
settings put global ro.PERCEPTIBLE_APP_ADJ 3
settings put global ro. HEAVY_WEIGHT_APP_ADJ 4
settings put global ro.app. optimization true
settings put global ro.launcher. dynamic true
settings put global ro.launcher. label. fastupdate true
settings put global device_idle_constants idle_duration=0
settings put global hidden_api_policy 1
settings put global hidden_api_policy_p_apps 1
settings put global hidden_api_policy_pre_p_apps 1
settings put global persist.omh.enabled 0
settings put global persist.service.lgospd.enable 0
settings put global persist. service.pcsync.enable 0
settings put global persist.sys. ssr.enable_debug 0
settings put global persist.sys.ssr.enable_ramdumps 0
settings put global persist.sys.ssr.restart_level 1
settings put global persist.sys. ap. restart_level 1
settings put global persist.sys.enable_strategy true
settings put global persist.rcs.supported 0
settings put global persist.data.profile_update true
settings put global persist.data. mode concurrent
settings put global persist.data. netmgrd. qos. enable true
settings put global persist.data. tcpackprio. enable true
settings put global persist.data.iwlan.enable true
settings put global persist.data.wda.enable true
settings put global persist.rmnet.data.enable true
settings put global persist.net. doxlat true
settings put global ro.use_data_netmgrd true
settings put global ro.com.android.dataroaming false
settings put global ro. ril.enable. managed. roaming 0
settings put global ro.wcn enabled
settings put global ro.config.ehrpd true
settings put global debug.bt.lowspeed true
settings put global debug.bt. discoverable_time 0
settings put global ro. ril.avoid. pdp.overlap 1
settings put global ro.ril.sensor.sleep. control 0
settings put global ro.config.hw_ReduceSAR true
settings put global radio_bounce 1
settings put global persist.radio. NETWORK_SWITCH 2
settings put global persist.radio. no_wait_for_card 1
settings put global persist.radio. data_no_toggle 1
settings put global persist. radio.data_con_rprt true
settings put global persist.radio. data_ltd_sys_ind 1
settings put global persist.radio.add_power_save 1
settings put global persist.radio.jbims 1
settings put global persist. ril.uart.flowctrl 99
settings put global persist.sys.gz. enable false
settings put global persist.gps.qc_nlp_in_use 0
settings put global hw.nogps true
settings put global ro.pip.gated 0
settings put global ro.config.hw_gps_power_track false
settings put global ro.config. hw_support_geofence false
settings put global config.disable_location true
settings put global location_mode 0
settings put global location_global_kill_switch 1
settings put global ro.support.signalsmooth true
settings put global ro.config.combined_signal true
settings put global ro.allow.mock. location 1
settings put global ro.com.google.locationfeatures 0
settings put global ro.com.google.networklocation 0
settings put global ro.gps.agps_provider 0
settings put global ro. ril.def.agps. feature 0
settings put global ro. ril.def.agps. mode 0
settings put global ro. vendor.net.enable_sla 1
settings put global net.tethering.noprovisioning true
settings put global security.perf_harden 0
settings put global persist.sys.resolution_change 1
settings put global ro.vendor.display.mode_change_optimize. enable true
settings put global ro.vendor. display.switch_resolution. support 1
settings put global ro. vendor.display.video_or_camera_fps.support true
settings put global ro.vendor. fps.switch. thermal true
settings put global ro.surface_flinger.protected_contents true
settings put global ro.surface_flinger.force_hwc_copy_for_virtual_displays true
settings put global ro.surface_flinger.running_without_sync_framework false
settings put global ro.surface_flinger.supports_background_blur 0
settings put global ro.surface_flinger.support_kernel_idle_timer true
settings put global ro.surface_flinger.set_display_power_timer_ms 100
settings put global ro.surface_flinger.set_idle_timer_ms 250
settings put global ro.surface_flinger.set_touch_timer_ms 500
settings put global ro.surface_flinger.set_fps_stat_timer_ms 750
settings put global ro.surface_flinger.vsync_event_phase_offset_ns 0
settings put global ro.surface_flinger.vsync_sf_event_phase_offset_ns 0
settings put global ro.surface_flinger.present_time_offset_from_vsync_ns 0
settings put global ro.surface_flinger. use_content_detection_for_refresh_rate true
settings put global ro. surface_flinger.refresh_rate_switching true
settings put global ro.surface_flinger.enable_layer_caching true
settings put global ro.surface_flinger.layer_caching_active_layer_timeout_ms 0
settings put global ro.surface_flinger.use_context_priority true
settings put global ro.surface_flinger.start_graphics_allocator_service true
settings put global ro.surface_flinger.uclamp. min 0
settings put global ro.surface_flinger.max_frame_buffer_acquired_buffers 1
settings put global ro.surface_flinger.has_wide_color_display false
settings put global persist.sys.color. adaptive true
settings put global persist.sys.sf.color_saturation 1. 0
settings put global persist.sys.brightness.low. gamma true
settings put global persist.sys. sf.native_mode 2
settings put global persist.sys.sf. hs_mode 0
settings put global persist.sys.sf.disable_blurs 1
settings put global persist.sys. static_blur_mode false
settings put global persist.sys. disable_blur_view true
settings put global persist.perf.wm_static_blur true
settings put global sys.output. 10bit true
settings put global sys.fb.bits 32
settings put global persist.sys.shadow.open 0
settings put global persist.sys. use_16bpp_alpha 0
settings put global persist. sys.purgeable_assets 0
settings put global persist.sys.scrollingcache 2
settings put global ro.vendor.perf.scroll_opt true
settings put global ro.vendor. perf.scroll_opt. heavy_app true
settings put global ro.vendor. scroll. preobtain. enable true
settings put global vendor.perf.gestureflingboost.enable true
settings put global ro.min_pointer_dur 1
settings put global ro.max. fling_velocity 12000
settings put global ro.min. fling_velocity 4000
settings put global windowsmgr.max_events_per_sec 150
settings put global ro.launcher.blur.appLaunch 0
settings put global iop.enable_prefetch_ofr 1
settings put global iop.enable_uxe 1
settings put global iop. enable_iop 1
settings put global vendor.perf.iop_v3.enable true
settings put global vendor.perf.iop_v3.enable. debug false
settings put global vendor.perf.workloadclassifier.enable true
settings put global ro.vendor.iocgrp.config 1
settings put global persist.sys.autoclearsave 2
settings put global persist.sys. enable_ioprefetch true
settings put global persist.mm.enable. prefetch true
settings put global mm.enable.smoothstreaming true
settings put global debug.media.video.frc false
settings put global debug.media. video.vpp false
settings put global sys.media.vdec.sw 1
settings put global ro.vendor.media_performance_class 0
settings put global ro.config.hw_media_flags 2
settings put global ro.mediaScanner.enable false
settings put global ro.media.maxresolution 0
settings put global ro.media. dec. aud.wma.enabled 1
settings put global ro.media. dec.vid.wmv.enabled 1
settings put global media.stagefright.thumbnail.prefer_hw_codecs true
settings put global media. stagefright.use-awesome true
settings put global media.stagefright.enable-record false
settings put global media.stagefright.enable-scan false
settings put global media.stagefright.enable-meta true
settings put global media.stagefright.enable-http true
settings put global media.enable-commonsource true
settings put global persist.media.lowlatency.enable true
settings put global persist.media. hls.enhancements true
settings put global persist.media. treble_omx false
settings put global av.debug.disable. pers.cache 0
settings put global aaudio.mmap_policy 1
settings put global aaudio.mmap_exclusive_policy 2
settings put global audio.legacy.postproc true
settings put global audio.deep_buffer. media true
settings put global audio.parser.ip.buffer. size 0
settings put global audio.offload.video true
settings put global audio.offload.track.enable true
settings put global audio.offload.passthrough false
settings put global audio. offload.gapless.enabled true
settings put global audio.offload.multiple. enabled true
settings put global audio.offload.pcm.16bit.enable false
settings put global audio.offload.pcm.24bit.enable false
settings put global audio.track.enablemonoorstereo 1
settings put global ro.have_aacencode_feature 1
settings put global ro. vendor.audio_tunning.nr 1
settings put global vendor.audio. lowpower true
settings put global vendor.audio. use. sw. alac. decoder true
settings put global vendor.audio.use.sw. ape.decoder true
settings put global lpa.use-stagefright true
settings put global lpa.decode false
settings put global lpa.encode false
settings put global tunnel.decode false
settings put global tunnel.encode false
settings put global persist.sys.audio.source true
settings put global persist.speaker.prot.enable false
settings put global persist.audio.hp true
settings put global persist.audio. hifi true
settings put global ro.config.hifi_always_on true
settings put global ro.config.hifi_enhance_support 1
settings put global ro. vendor.audio.game. effect true
settings put global ro.vendor. audio.spk.clean true
settings put global ro.audio.soundfx.dirac true
settings put global audio.sys.routing.latency 0
settings put global audio.sys.mute.latency. factor 2
settings put global mpq.audio.decode true
settings put global debug.stagefright.ccodec 1
settings put global debug.stagefright.omx_default_rank 0
settings put global debug. stagefright.omx_default_rank. sw-audio 1
settings put global vendor.media.omx 0
settings put global af.fast_track_multiplier 1
settings put global af.thread. throttle 0
settings put global ota_disable_automatic_update 1
settings put global drm.service.enabled true
settings put global vendor.hwc.drm.scale_with_gpu 1
settings put global persist.vendor.firmware.update true
settings put global persist.vendor.battery.health true
settings put global persist.vendor. battery.health.optimise true
settings put global persist.vendor. accelerate. charge true
settings put global persist.vendor.low. cutoff true
settings put global persist.vendor. cool.mode true
settings put global persist.vendor.cne.feature 1
settings put global persist.vendor. dpm.feature 1
settings put global persist. vendor. dpm.tcm 1
settings put global persist.vendor.dc.enable 2
settings put global persist.sys.support.vt false
settings put global persist.sys. softdetector.enable false
settings put global ro.sf.use_latest_hwc_vsync_period 1
settings put global ro.sf. blurs_are_expensive 0
settings put global ro.sf. compbypass. enable 1
settings put global ro.compcache.default 1
settings put global enable_gpu_debug_layers 0
settings put global sys.tp.grip_enable 1
settings put global sys.use_fifo_ui 1
settings put global sys_vdso 1
settings put global sys.enable_lpm 1
settings put global ro.vndk.lite true
settings put global ro.recentMode 0
settings put global persist.vendor.enable. hans true
settings put global ro.amlogic.no. preloadclass 0
settings put global ro.config.rm_preload_enabled 1
settings put global ro. storage_manager.enabled true
settings put global storage. preload.complete 1
settings put global persist.dummy_storage 1
settings put global persist.sys.storage_preload 1
settings put global persist.sys.prelaunch. off 0
settings put global persist. sys.preloads.file_cache_expired 0
settings put global persist.vendor.enable.preload true
settings put global persist.preload.common 1
settings put global enable_app_prefetch 1
settings put global ro.quick_start_support 1
settings put global ro. zygote.preload. enable 1
settings put global ro.zygote.preload. disable 2
settings put global ro.zygote.disable_gl_preload false
settings put global persist.zygote.preload_threads 2
settings put global persist.sys.preload.preload_num 2
settings put global persist. sys.preLoadDrawable. debug false
settings put global persist.sys. preLoadDrawable.enable true
settings put global persist.sys. boost. launch 1
settings put global persist. sys.powersave.rotate 1
settings put global persist.irqbalance.enable true
settings put global persist.device_config.runtime_native. use_app_image_startup_cache true
settings put global persist.device_config.runtime_native.usap_pool_enabled true
settings put global persist.device_config.runtime_native.usap_pool_size_min 1
settings put global persist.device_config.runtime_native.usap_refill_threshold 1
settings put global persist.device_config.runtime_native_boot. iorap_readahead_enable true
settings put global persist.device_config.runtime_native_boot. iorap_perfetto_enable false
settings put global persist.device_config.runtime_native. metrics. reporting-mods 0
settings put global persist. device_config.runtime_native. metrics.reporting-mods-server 0
settings put global persist. device_config.runtime_native. metrics.write-to-statsd false
settings put global ro.service.remove_unused 1
settings put global ro. iorapd.enable true
settings put global iorapd.perfetto.enable false
settings put global iorapd.readahead. enable true
settings put global ro.kernel.ebpf.supported true
settings put global sys.ipo.disable 0
settings put global ro.mtk_ipo_support 1
settings put global ro. mtk_perfservice_support 1
settings put global ro.mtk_bg_power_saving_support 1
settings put global ro.mtk_bg_power_saving_ui 1
settings put global vendor.mtk_thumbnail_optimization true
settings put global def_bg_power_saving 1
settings put global persist.bg. dexopt.enable true
settings put global persist.sys.ps. enable 1
settings put global background_gpu_usage 0
settings put global persist.sys.gamespeed.enable true
settings put global sys.games.gt.prof 1
settings put global ro.config.gameassist 1
settings put global debug.game.video.support true
settings put global debug.enable. gamed 1
settings put global debug. slsi_platform 1
settings put global debug.sqlite.journalmode OFF
settings put global debug.sqlite.syncmode OFF
settings put global debug.sqlite. wal.syncmode OFF
settings put global ro.vendor.gpu.dataspace 1
settings put global ro.incremental.enable 1
settings put global ro.fb.mode 1
settings put global ro. tb.mode 1
settings put global ro. ril.hsupa.category 6
settings put global ro.ril.hsdpa.category 8
settings put global ro.ril.gprsclass 10
settings put global ro.ril.hsdpa.dbdc 1
settings put global ro. ril.hsxpa 2
settings put global ro.ril.enable.sdr 0
settings put global ro.ril.enable.a52 1
settings put global ro. ril.enable.dtm 0
settings put global ro.ril.enable.amr. wideband 1
settings put global ro.ril.enable.imc. feature 1
settings put global ro. ril.enable.enhance.search 1
settings put global ro. ril.enable.pre_r8fd 1
settings put global ro. ril.enable.nitz 0
settings put global ro.ril.disable.cpc 1
settings put global ro. ril.fast. dormancy. rule 0
settings put global ro. fast.dormancy 0
settings put global ro.product.enhanced_4g_lte true
settings put global ro.telephony.call_ring. multiple false
settings put global sys.fflag.override. settings_seamless_transfer true
settings put global persist.vendor.data.mode offload
settings put global persist.vendor.mwqem.enable 1
settings put global vendor.debug.egl.swapinterval 0
settings put global debug.gr.swapinterval 0
settings put global ro.vold.umsdirtyratio 1
settings put global debug.cpuprio 1
settings put global debug.gpuprio 1
settings put global debug. ioprio 1
settings put global debug.hang.count 0
settings put global debug. kill_allocating_task 1
settings put global ro.config.upgrade_appkill true
settings put global ro.lmk.kill_heaviest_task true
settings put global ro.lmk.use_minfree_levels true
settings put global ro.lmk.vmpressurenhanced true
settings put global persist.vendor.memplus.enable 1
settings put global persist.sys.ramboost.enable true
settings put global persist.sys. ramboost. ioppreload true
settings put global persist.sys. ramboost.olmemplus_option 2
settings put global persist.sys. memctrl on
settings put global ro.memperf.enable true
settings put global native_memtag_sync 1
settings put global ram_expand_size_list 1
settings put global sys.is_mem_low_level 1
settings put global sys.use_memfd true
settings put global sys.config.bigdata_enable true
settings put global sys.config. bigdata_mem_enable true
settings put global ro.config.per_app_memcg true
settings put global ro.config. low_mem true
settings put global ro.config. low_ram true
settings put global ro.config.low_ram. mod true
settings put global ro.board_ram_size low
settings put global ro.ime.lowmemory true
settings put global ro.am.enabled_low_mem_maint true
settings put global ro.am.no_kill_cached_processes_until_boot_completed true
settings put global ro.am. no_kill_cached_processes_post_boot_completed_duration_millis 0
settings put global ro. ksm.default 1
settings put global ro.cp_system_other_odex 1
settings put global ro.config.hw_pg_frz_all true
settings put global ro.config. dha_pwhitelist_enable 1
settings put global ro. config.dha_tunnable 1
settings put global ro.has. cpu.setting true
settings put global ro.cpufreq.game 1
settings put global ro.core_ctl_min_cpu 0
settings put global ro.core_ctl_present 1
settings put global ro.thermal_warmreset true
settings put global ro.config.enable_thermal_bdata true
settings put global persist.sys.thermal_policy_update 1
settings put global persist.sys.thermal. enable 1
settings put global persist.thermalmanager.enable true
settings put global thermal_offload 0
settings put global allow_heat_cooldown_always 1
settings put global persist.sys. lowcost 1
settings put global persist.sys.binary_xml false
settings put global unused_static_shared_lib_min_cache_period_ms 250
settings put global cached_apps_freezer enabled
settings put global persist.device_config.use_cgroup_freezer true
settings put global app_restriction_enabled true
settings put global app_auto_restriction_enabled 1
settings put global app_standby_enabled 1
settings put global forced_app_standby_enabled 1
settings put global keep_profile_in_background 0
settings put global always_finish_activities 1
settings put global sys.app. oom_adj 1
settings put global sys. isdumpstaterunning 0
settings put global sys.config.spcm_enable true
settings put global sys.config. samp_spcm_enable true
settings put global sys.config.spcm_preload_enable true
settings put global sys.config.spcm_kill_skip true
settings put global sys.config. spcm_gcm_kill_enable false
settings put global sys.config. spcm_db_enable false
settings put global sys.config. spcm_db_launcher false
settings put global sys.config. samp_oak_enable false
settings put global sys.config.samp_oakoom_enable false
settings put global sys.settings.support 1
settings put global persist.sys.ss. enable false
settings put global persist.sys. pwctl.enable 0
settings put global sys. ipo.pwrdncap 0
settings put global dynamic_power_savings_enabled 1
settings put global adaptive_battery_management_enabled 0
settings put global battery_saver_constants "vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,fullbackup_deferred=true,keyvaluebackup_deferred=true,gps_mode=low_power,data_saver_enabled=true"
settings put global sched. colocate. enable 1
settings put global debug.smart_scheduling 1
settings put global persist.sys.io_scheduler noop
settings put global sys.io. scheduler noop
settings put global sys.start. first 1
settings put global ro.am.reschedule_service true
settings put global ro.sys.fw.bservice_enable true
settings put global ro.sys. fw.force_adoptable true
settings put global debug.hwui.disable_vsync 0
settings put global debug.hwui.disable_gpu_cache false
settings put global cache. trigger 1
settings put global service. sf.prime_shader_cache 1
settings put global service.sf.present_timestamp 0
settings put global persist.sys.engpc.disable 0
settings put global persist.enable_task_snapshots false
settings put global ro.config.fha_enable true
settings put global ro.config. enable_rcc true
settings put global ro.config. sync 0
settings put global max_empty_time_millis 0
settings put global fstrim_mandatory_interval 1
settings put global ro.sys.fw.use_trim_settings true
settings put global ro.sys.fw.trim_empty_percent 50
settings put global ro.sys. fw.trim_cache_percent 50
settings put global ro.sys. fw.empty_app_percent 25
settings put global ro.trim. config true
settings put global ro.trim. memory. launcher 1
settings put global ro. trim.memory.font_cache 1
settings put global ro. zstd.default_compression_level 1
settings put global vold.post_fs_data_done 1
settings put global vold.storage. prepared 1
settings put global vold.has_compress 1
settings put global vold. has_quota 0
settings put global vold.should_defrag 1
settings put global vold.checkpoint_committed 1
settings put global ro.storaged.event. interval 999999
settings put global gadget.nand.force_sync true
settings put global virtualsd.enable true
settings put global pm.sdwake. enabled true
settings put global ro.DontUseAnimate yes
settings put global debug.hwui.force_dark true
settings put global debug.hwui.perfetto_profile_mode both
settings put global debug.performance. tuning 1
settings put global debug.gralloc.map_fb_memory 1
settings put global debug.gralloc.enable_fb_ubwc 1
settings put global debug.gralloc.gfx_ubwc_disable 0
settings put global debug. gralloc.disable_hardware_buffer 1
settings put global debug.gr.numframebuffers 1
settings put global persist.smart_pool 1
settings put global ro.hardware.gralloc default
settings put global ro.hardware. respect_als true
settings put global ro.hardware. hwcomposer default
settings put global ro.hwui.render_ahead 1
settings put global debug.hwui.renderer_mode 1
settings put global debug.hwui.level 0
settings put global debug.hwui.swap_with_damage false
settings put global debug.hwui.render_dirty_regions false
settings put global debug.hwui.show_dirty_regions false
settings put global debug.hwui.use_gpu_pixel_buffers false
settings put global debug. hwui.disabledither true
settings put global debug.hwui.disable_draw_defer true
settings put global debug.hwui.disable_draw_reorder true
settings put global debug.hwui.show_draw_order 0
settings put global debug.hwui.show_draw_calls 0
settings put global debug. hwui.enable_bp_cache true
settings put global debug.hwui.use_small_cache 1
settings put global sysui_tuner_enabled 0
settings put global sysui_font_cache_persist true
settings put global persist.sys.font 2
settings put global persist.sys. font_clarity 0
settings put global persist.sys. force_highendgfx true
settings put global ro.config.avoid_gfx_accel false
settings put global rs. gpu.rsIntrinsic 0
settings put global rs.gpu.filterscript 0
settings put global rs. gpu.renderscript 0
settings put global debug.rs.debug 0
settings put global debug.rs. visual 0
settings put global debug.rs.reduce 1
settings put global debug.rs. shader 0
settings put global debug. rs.shader. attributes 0
settings put global debug. rs.shader.uniforms 0
settings put global ro.graphics.hwcomposer.kvm true
settings put global fku.perf.profile 1
settings put global graphics.gpu.profiler.support true
settings put global force_gpu_render 1
settings put global force_gpu_rendering 1
settings put global gpu_rendering_mode 1
settings put global opengl_renderer 1
settings put global opengl_trace false
settings put global vendor.display.enable_fb_scaling 1
settings put global vendor. display.use_layer_ext 1
settings put global vendor. display.enable_posted_start_dyn 1
settings put global vendor.display.comp_mask 0
settings put global vendor. display.enable_perf_hint_large_comp_cycle 1
settings put global vendor. display.disable_decimation 0
settings put global vendor.display. disable_ui_3d_tonemap 1
settings put global vendor.display. enable_rotator_ui 1
settings put global vendor.display.skip_refresh_rate_change 1
settings put global sdm.perf_hint_window 50
settings put global ro.mtk_perf_fast_start_win 1
settings put global ro. mtk_perf_simple_start_win 1
settings put global ro.mtk_perf_response_time 1
settings put global persist.sys.max_rdh_delay 0
settings put global persist. sys.performance true
settings put global persist.sys. cpuset. enable 1
settings put global persist. sys.cpuset.subswitch 1
settings put global persist.sys. iaware. cpuenable true
settings put global persist.sys. iaware.vsyncfirst true
settings put global persist. sys.enable_iaware true
settings put global persist.sys. periodic. enable true
settings put global persist.tuning. qdcm 1
settings put global sys.iaware. eas.on true
settings put global debug.force_no_blanking true
settings put global ro.bq.gpu_to_cpu_unsupported 1
settings put global ro.product.gpu. driver 1
settings put global ro.vendor.gpu.boost 1
settings put global multi_sampling_enabled 0
settings put global persist.sampling_profiler 0
settings put global dev.pm.dyn_samplingrate 1
settings put global cpu.fps auto
settings put global gpu.fps auto
settings put global persist.sys.fpsctrl.enable 1
settings put global persist.sys.autofps.mode 1
settings put global sys.perf.heavy false
settings put global sys.perf.status false
settings put global sys.perf.zygote true
settings put global sys.perf.iop true
settings put global sys.perf.schd true
settings put global sys. perf.hmp 6:2
settings put global sys.perf. fbooster true
settings put global sys.perf.tbooster true
settings put global sys. hwc.gpu_perf_mode 1
settings put global ro.qualcomm.perf.cores_online 2
settings put global ro.hw.use_hwc_cpu_perf_mode 1
settings put global ro.hw.use_disable_composition_type_gles 0
settings put global ro.hwc.legacy_api true
settings put global hwc.scenario 2
settings put global hw2d.force 1
settings put global hw3d.force 1
settings put global persist.sys.force_hw_ui true
settings put global persist.sys. ui. hw 1
settings put global persist.sys.oem_smooth 1
settings put global persist.sys. force_sw_gles 1
settings put global ro.kernel.qemu. gles 1
settings put global ro.config.hw_wfd_optimize true
settings put global persist.sys.wfd. virtual 0
settings put global persist.sys. jankenable false
settings put global persist.hwc.ptor. enable true
settings put global persist.hwc.mdpcomp.enable true
settings put global persist.hwc.pubypass true
settings put global persist.hwc2.skip_client_color_transform true
settings put global com.qc.hardware true
settings put global debug.qc.hardware true
settings put global debug.composition.type gpu
settings put global debug.cpurend.vsync true
settings put global debug.gpurend.vsync true
settings put global debug.enabletr true
settings put global debug.sf.layer_timeout 0
settings put global debug.sf. layer_smoothness 1
settings put global debug.sf. no_hw_vsync 0
settings put global debug.sf.ddms 0
settings put global debug.sf.hw 1
settings put global debug.sf. enable_hgl 1
settings put global debug.sf.enable_hwc_vds 0
settings put global debug.sf. swaprect 1
settings put global debug.sf. gpu_freq_index 1
settings put global debug.sf. perf_mode 1
settings put global debug.gfx.driver 1
settings put global debug. gl.hw 1
settings put global debug.egl.hw 1
settings put global debug.egl.profiler 1
settings put global debug.egl.force_msaa 1
settings put global debug.egl.native_scaling 1
settings put global debug. overlayui.enable 0
settings put global debug.sf.gpuoverlay 0
settings put global debug.sf. viewmotion 0
settings put global debug. sf.high_fps_late_app_phase_offset_ns 0
settings put global debug.sf.high_fps_late_sf_phase_offset_ns 0
settings put global debug.sf. enable_advanced_sf_phase_offset 1
settings put global debug.sf.enable_gl_backpressure 1
settings put global debug.sf.latch_unsignaled 1
settings put global debug.sf.auto_latch_unsignaled 0
settings put global debug.sf. recomputecrop 0
settings put global debug.sf. use_phase_offsets_as_durations 1
settings put global debug.sf.disable_client_composition_cache 0
settings put global debug.egl.buffcount 1
settings put global debug. egl.debug_proc 0
settings put global debug. egl.trace 0
settings put global debug.egl.callstack 0
settings put global debug.egl.finish 1
settings put global debug.sf.showupdates 0
settings put global debug.sf. showcpu 0
settings put global debug. sf.showbackground 0
settings put global debug.sf.showfps 0
settings put global debug.sf.dump 0
settings put global debug.sf.enable_egl_image_tracker 0
settings put global debug.sf. predict_hwc_composition_strategy 1
settings put global debug.sf. enable_planner_prediction true
settings put global debug.sf. gpu_comp_tiling 1
settings put global debug.enable. sglscale 1
settings put global debug.qctwa.preservebuf 1
settings put global debug. mdpcomp.idletime 0
settings put global debug. mdpcomp.maxlayer 0
settings put global debug. doze.component 0
settings put global debug.migrate. bigcore false
settings put global debug.sdm.support_writeback 1
settings put global sdm.debug.disable_rotator_downscale 1
settings put global sdm.debug.disable_skip_validate 1
settings put global sdm.debug.disable_dest_sc 1
settings put global sdm. debug.disable_scalar 1
settings put global sdm. debug.disable_avr 1
settings put global hotword_detection_enabled 0
settings put global ro.hw.gyroscope false
settings put global ro.config.hw_temperature_warn true
settings put global ro.config. hw_sensorhub false
settings put global ro.vendor.sensors.rawdata_mode false
settings put global ro.vendor. sensors.pedometer false
settings put global ro.vendor. 
