#!/usr/bin/env bash

printf '%s\n' "Setup"
export LC_ALL=C LANG=C

sync
pacman -S 
if ! command -v adb &>/dev/null; then
  if command -v pacman &>/dev/null; then
    sudo pacman -Sq --noconfirm --needed android-tools
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install android-tools -yq
  fi
fi

adb start-server
adb devices

# https://github.com/vaginessa/adb-cheatsheet
adb shell sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.api

printf '%s\n' "Maintenance"
adb shell sync
adb shell cmd stats write-to-disk
adb shell settings put global fstrim_mandatory_interval 1
adb shell pm art cleanup
adb shell pm trim-caches 128G
adb shell cmd shortcut reset-all-throttling
adb shell logcat -b all -c
adb shell logcat -c
adb shell wm density reset
adb shell wm size reset
adb shell sm fstrim
adb shell cmd activity idle-maintenance
adb shell cmd system_update
adb shell cmd otadexopt cleanup
# Prob root only
adb shell wipe cache
adb shell recovery --wipe_cache

printf '%s\n' "Cleanup"
adb shell rm -rf "**/*.tmp"
adb shell rm -rf "**/*.log"
adb shell rm -rf "**/*.tmp"
adb shell rm -rf "**/*.bak"

printf '%s\n' "Optimizing ART..."
adb shell pm bg-dexopt-job --enable
# Run any postponed dex‐opt jobs immediately 
adb shell cmd jobscheduler run -f android \
  $(adb shell cmd jobscheduler list-jobs android \
  | grep background-dexopt | awk '{print $2}')

# Does it twice to force speed-profile for all and does only speed for apps that might benefit without overwriting
adb shell cmd package compile -af --full --secondary-dex -m speed-profile
adb shell cmd package compile -a  -f --full --secondary-dex -m speed
adb shell pm art dexopt-packages -r bg-dexopt

# Cpu
adb shell cmd thermalservice override-status 1

# Net
adb shell cmd netpolicy set restrict-background true

printf '%s\n' "Rendering tweaks..."
adb shell setprop debug.composition.type dyn
adb shell setprop debug.fb.rgb565 0
adb shell setprop debug.sf.disable_threaded_present false
adb shell setprop debug.sf.predict_hwc_composition_strategy 1
adb shell setprop debug.hwui.use_buffer_age true
adb shell settings put global force_gpu_rendering 1
adb shell settings put global debug.hwui.force_gpu_command_drawing 1
adb shell settings put global debug.hwui.use_disable_overdraw 1
adb shell settings put global skia.force_gl_texture 1
adb shell settings put global overlay_disable_force_hwc 1
adb shell settings put global disable_hw_overlays 1
adb shell settings put global video.accelerate.hw 1
adb shell settings put global media.sf.hwaccel 1
    adb shell settings put global enable_hardware_acceleration 1
    adb shell settings put global hardware_accelerated_rendering_enabled 1
    adb shell settings put global hardware_accelerated_graphics_decoding 1
    adb shell settings put global hardware_accelerated_video_decode 1
    adb shell settings put global hardware_accelerated_video_encode 1

adb shell setprop debug.sf.predict_hwc_composition_strategy 1
debug.sf.gpu_comp_tiling 1
debug.enable.sglscale 1
debug.sdm.support_writeback 1
debug.sf.disable_client_composition_cache 0
debug.sf.use_phase_offsets_as_durations 1
debug.sf.enable_gl_backpressure 1
debug.sf.enable_advanced_sf_phase_offset 1
debug.egl.native_scaling 1
debug.egl.hw 1
debug.gl.hw 1
debug.sf.hw 1
debug.sf.no_hw_vsync 1
debug.sf.ddms 0
debug.sf.hw 1
debug.sf.enable_hgl 1
debug.sf.enable_hwc_vds 0
debug.gfx.driver 1
debug.sf.perf_mode 1
debug.enabletr true
debug.qc.hardware true
adb shell settings put global hw2d.force 1
adb shell settings put global hw3d.force 1
adb shell settings put global multi_sampling_enabled 0
debug.rs.reduce 1
adb shell settings put global sysui_font_cache_persist true
debug.hwui.use_gpu_pixel_buffers false
debug.hwui.renderer_mode 1
debug.hwui.disabledither true
debug.hwui.enable_bp_cache true
debug.gralloc.map_fb_memory 1
debug.gralloc.enable_fb_ubwc 1
debug.gralloc.gfx_ubwc_disable 0
debug.gralloc.disable_hardware_buffer 1
debug.smart_scheduling 1
debug.hwui.disable_gpu_cache false
debug.gr.swapinterval 0
debug.egl.swapinterval 0
debug.slsi_platform 1
debug.sqlite.journalmode OFF
debug.sqlite.syncmode OFF
debug.sqlite.wal.syncmode ON
debug.stagefright.ccodec 1
debug.syncopts 3

printf '%s\n' "Audio tweaks..."
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
debug.media.video.frc false
debug.media.video.vpp false


adb shell settings put global battery_saver_constants \ 
  "vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,fullbackup_deferred=true,keyvaluebackup_deferred=true, \
  gps_mode=low_power,data_saver=true,optional_sensors_disabled=true,advertiser_id_enabled=false"
adb shell settings put global dynamic_power_savings_enabled 1
adb shell settings put global adaptive_battery_management_enabled 0
adb shell settings put global app_auto_restriction_enabled 1
adb shell settings put global app_restriction_enabled true
adb shell settings put global cached_apps_freezer enabled
adb shell settings put global allow_heat_cooldown_always 1
adb shell settings put global ram_expand_size_list 1
adb shell settings put global native_memtag_sync 1
adb shell settings put global background_gpu_usage 0
adb shell settings put global enable_app_prefetch 1
adb shell settings put global storage.preload.complete 1
adb shell settings put global ota_disable_automatic_update 1


printf '%s\n' "Configuring Vulkan..."
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

adb shell settings put global data_saver_mode 1
 adb shell settings put global ro.wifi.signal.optimized true

printf '%s\n' "Configuring Webview..."
echo "webview --enable-features=DeferImplInvalidation,ScrollUpdateOptimizations" > /data/local/tmp/webview-command-line
adb shell chmod 644 /data/local/tmp/webview-command-line
adb shell cmd webviewupdate set-webview-implementation com.android.webview.beta

printf '%s\n' "Configuring ANGLE..."
angle_on(){
  adb shell settings put global angle_gl_driver_all_angle 1
  adb shell settings put global angle_debug_package com.android.angle
  adb shell settings put global angle_gl_driver_selection_values angle
  adb shell settings put global angle_gl_driver_selection_pkgs com.android.webview,com.android.webview.beta
}
angle_off(){
  adb shell settings delete global angle_debug_package
  adb shell settings delete global angle_gl_driver_all_angle
  adb shell settings delete global angle_gl_driver_selection_values
  adb shell settings delete global angle_gl_driver_selection_pkgs
}
angle_on

driver(){
  adb shell settings put global enhanced_processing 2
  adb shell settings put global enhanced_cpu_responsiveness 1
  adb shell settings put global sem_enhanced_cpu_responsiveness 1
  adb shell settings put global restricted_device_performance 1,0
  adb shell settings put global omap.enhancement true
  
    adb shell settings put global game_low_latency_mode 1
    adb shell settings put global game_gpu_optimizing 1
    adb shell settings put global game_driver_mode 1
    adb shell settings put global game_driver_all_apps 1
    adb shell settings put global game_driver_opt_out_apps 1
    adb shell settings put global updatable_driver_all_apps 1
    adb shell settings put global updatable_driver_production_opt_out_apps 1
    

printf '%s\n' "Logs..."
adb shell logcat -G 128K -b main -b system
adb shell logcat -G 64K -b radio -b events -b crash
adb shell cmd display ab-logging-disable
adb shell cmd display dwb-logging-disable
adb shell cmd looper_stats disable
adb shell dumpsys power set_sampling_rate 0

printf '%s\n' "Performance tweaks..."
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
    adb shell device_config put launcher enable_quick_launch_v2 true
    

printf '%s\n' "Battery tweaks..."
adb shell cmd power suppress-ambient-display true
adb shell cmd power set-face-down-detector false
# adb shell cmd power set-mode 1/0
adb shell cmd power set-fixed-performance-mode-enabled false
# adb shell cmd power set-fixed-performance-mode-enabled true/false
adb shell cmd power set-adaptive-power-saver-enabled true
# adb shell cmd power set-adaptive-power-saver-enabled true/false
adb shell settings put system accelerometer_rotation 0

printf '%s\n' "Input tweaks"
    adb shell settings put global touch_calibration 1
    adb shell settings put global touch.size.bias 0
    adb shell settings put global touch.size.isSummed 0
    adb shell settings put global touch.size.scale 1
    adb shell settings put global touch.pressure.scale 0.1
    adb shell settings put global touch.distance.scale 0
    adb shell settings put secure touch_blocking_period 0.0
    adb shell settings put secure tap_duration_threshold 0.0
    adb shell settings put secure long_press_timeout 250
    adb shell settings put secure multi_press_timeout 250
    adb shell settings put global window_focus_timeout 250
    adb shell settings put global animator_duration_scale 0.0
    adb shell settings put global transition_animation_scale 0.0
    adb shell settings put global window_animation_scale 0.0
    adb shell settings put system slider_animation_duration 0.0
        adb shell settings put system remove_animations 1
    adb shell settings put system reduce_animations 1
adb shell settings put secure user_wait_timeout 0
adb shell settings put global view.scroll_friction 0
    adb shell settings put global reduce_transitions 1
    adb shell settings put global shadow_animation_scale 0
    adb shell settings put global render_shadows_in_compositor false
    adb shell settings put global remove_animations 1
    adb shell settings put global fancy_ime_animations 0
 adb shell wm set-sandbox-display-apis true
 adb shell wm disable-blur true
 adb shell wm scaling off
 adb shell cmd display dwb-logging-disable
 adb shell cmd display ab-logging-disable
 adb shell cmd looper_stats disable
 adb shell device_config put systemui window_shadow 0
adb shell device_config put systemui window_blur 0
adb shell device_config put systemui window_cornerRadius 0


printf '%s\n' "Other"
adb shell settings put global gpu_rasterization_forced 1
adb shell settings put global enable_lcd_text 1
adb shell setprop debug.aw.power_scheduler_enable_idle_throttle 1
adb shell setprop debug.aw.cpu_affinity_little 1
adb shell setprop debug.sf.disable_backpressure 0
adb shell setprop debug.debuggerd.disable 1
adb shell setprop debug.sf.enable_hwc_vds 1
adb shell setprop debug.tracing.mnc 0
adb shell setprop debug.tracing.battery_status 0
adb shell setprop debug.tracing.screen_state 0
adb shell settings put global renderthread.skia.reduceopstasksplitting true
adb shell settings put global skia.force_gl_texture 1
adb shell settings put global multipath-tcp-enable 1
adb shell settings put secure USAGE_METRICS_UPLOAD_ENABLED 0
adb shell settings put secure usage_metrics_marketing_enabled 0
adb shell settings put secure limit_ad_tracking 1
adb shell settings put system multicore_packet_scheduler 1
adb shell settings put system rakuten_denwa 0
adb shell settings put system send_security_reports 0
    adb shell settings put global package_usage_stats_enabled 0
    adb shell settings put global recent_usage_data_enabled 0
        adb shell settings put global show_non_market_apps_error 0
    adb shell settings put global app_usage_enabled 0
    adb shell settings put global media.metrics.enabled 0
    adb shell settings put global media.metrics 0
adb shell settings put global data_saver_mode 1
adb shell settings put global mobile_data_always_on 0
adb shell settings put global mobile_data_keepalive_enabled 0
adb shell settings put global ble_scan_always_enabled 0
adb shell settings put global hotword_detection_enabled 0
adb shell settings put global wifi_scan_always_enabled 0
adb shell settings put global wifi_watchdog_roaming 0
 adb shell settings put global network_scoring_ui_enabled 0
 adb shell settings put global network_avoid_bad_wifi 1
adb shell cmd netpolicy set restrict-background true
adb shell settings put global wifi_suspend_optimizations_enabled 2
adb shell settings put global wifi_stability 1
adb shell settings put global webview_safe_browsing_enabled 0
adb shell settings put global private_dns_mode hostname
adb shell settings put global private_dns_specifier 
adb shell settings put global net.dns1
adb shell settings put global net.dns2
# Improve scroll responsiveness apparently
gfx_set(){ adb shell cmd gfxinfo "$1" reset && adb shell cmd gfxinfo "$1" framestats; }

# Aggressive AppStandby / Doze toggles
adb shell cmd deviceidle force-idle
adb shell cmd deviceidle unforce
adb shell dumpsys deviceidle whitelist +com.android.systemui

adb shell cmd uimode night yes 
adb shell cmd uimode car no
adb shell cmd -w wifi force-country-code enabled DE
adb shell cmd -w wifi force-low-latency-mode enabled
adb shell cmd wifi force-low-latency-mode enabled
adb shell cmd -w wifi force-hi-perf-mode enabled
adb shell cmd wifi force-hi-perf-mode enabled
# Sets the interval between RSSI polls to milliseconds.
#adb shell cmd -w wifi set-poll-rssi-interval-msecs <int>
adb shell cmd wifi set-scan-always-available disabled
adb shell cmd appops set com.google.android.gms START_FOREGROUND ignore
adb shell cmd appops set com.google.android.gms INSTANT_APP_START_FOREGROUND ignore
adb shell cmd appops set com.google.android.ims START_FOREGROUND ignore
adb shell cmd appops set com.google.android.ims INSTANT_APP_START_FOREGROUND ignore
adb shell dumpsys deviceidle whitelist +com.android.systemui

#Print all applications in use
adb shell pm list packages | sed -e "s/package://" | \
  while read x; do adb shell cmd package resolve-activity --brief $x | tail -n 1 | grep -v "No activity found"; done

# List all active services
#adb shell dumpsys -l
# Older devices
#adb shell dumpsys -l |sed 's/^  /      /g'

# Print codecs for bluetooth headphones
adb shell dumpsys media.audio_flinger | grep -A3 Input 

# Dump Settings
adb shell dumpsys settings

# Erase old stats for battery:
adb shell dumpsys batterystats --reset 

# Sort Applications By Ram Usage:
adb shell dumpsys meminfo

# Open Special Menu
# adb shell am start -a android.intent.action.VIEW \
# Open settings:
adb shell am start -n com.android.settings/com.android.settings.Settings
# Start prefered webbrowser:
adb shell am start -a android.intent.action.VIEW -d <url> (com.android.browser | com.android.chrome | com.sec.android.sbrowser)
# Open any URL in default browser
adb shell am start -a android.intent.action.VIEW -d <url>
# Print Activities:
adb shell am start -a com.android.settings/.wifi.CaptivePortalWebViewActivity

# Auto rotation off
adb shell content insert –uri content://settings/system –bind name:s:accelerometer_rotation –bind value:i:0
# Rotate portrait
adb shell content insert –uri content://settings/system –bind name:s:user_rotation –bind value:i:0

# Adopting USB-Drive
adb shell sm set-force-adoptable true

 adb shell settings put global enable_hardware_acceleration 1
    adb shell settings put global hardware_accelerated_rendering_enabled 1
    adb shell settings put global hardware_accelerated_graphics_decoding 1
    adb shell settings put global hardware_accelerated_video_decode 1
    adb shell settings put global hardware_accelerated_video_encode 1
    adb shell settings put global media.sf.hwaccel 1
    adb shell settings put global video.accelerate.hw 1
    adb shell settings put global ro.config.enable.hw_accel true
    adb shell settings put global debug.hwui.render_priority 1

# Print data in .db files, clean:
grep -vx -f <(sqlite3 Main.db .dump) <(sqlite3 ${DB} .schema) 
# Use below command fr update dg.db file:
sqlite3 /data/data/com.google.android.gms/databases/dg.db "update main set c='0' where a like '%attest%';" 


set_apk(){
  local mode="$1" apk="$2"
  case "$mode" in
    "dump") adb shell pm grant "$apk" android.permission.DUMP ;;
    "write") adb shell pm grant "$apk" android.permission.WRITE_SECURE_SETTINGS ;;
    "doze") adb shell dumpsys deviceidle whitelist +"$apk" ;;
  esac
}
set_apk dump com.pittvandewitt.wavelet


adb shell settings put secure systemui.google.opa_enabled 0
adb shell settings put system background_power_saving_enable 1
adb shell settings put system perf_profile performance
    adb shell settings put system intelligent_sleep_mode 0
    adb shell settings put system power_mode high
    adb shell settings put secure sensors_off 1
    adb shell settings put secure sensors_off_enabled 1
    adb shell settings put secure sensor_privacy 1
 adb shell settings put secure skip_gesture 0
 adb shell settings put secure silence_gesture 0
  adb shell settings put secure screensaver_enabled 0
  adb shell settings put secure reduce_bright_colors_activated 1
  adb shell settings put global accessibility_reduce_transparency 1
  
    adb shell settings put system bluetooth_discoverability 1
    adb shell settings put system motion_engine 0
    adb shell settings put system master_motion 0
    adb shell settings put system tube_amp_effect 1
    adb shell settings put system k2hd_effect 1
    adb shell device_config put systemui window_cornerRadius 0
    adb shell device_config put systemui window_blur 0
    adb shell device_config put systemui window_shadow 0
    adb shell device_config put graphics render_thread_priority high
    adb shell device_config put graphics enable_gpu_boost true
    adb shell device_config put graphics enable_cpu_boost true
    adb shell device_config put surfaceflinger set_max_frame_rate_multiplier 0.5
      adb shell device_config put runtime_native_boot pin_camera false
    adb shell device_config put launcher ENABLE_QUICK_LAUNCH_V2 true
    adb shell device_config put launcher enable_quick_launch_v2 true
    adb shell device_config put privacy location_access_check_enabled false
    adb shell device_config put privacy location_accuracy_enabled false
    adb shell device_config put privacy safety_protection_enabled true
    adb shell device_config put activity_manager use_compaction true
    adb shell device_config put activity_manager set_sync_disabled_for_tests persistent
    adb shell device_config put activity_manager enable_background_cpu_boost true
      adb shell cmd appops set com.google.android.gms START_FOREGROUND ignore
    adb shell cmd appops set com.google.android.gms INSTANT_APP_START_FOREGROUND ignore
    adb shell cmd appops set com.google.android.ims START_FOREGROUND ignore
    adb shell cmd appops set com.google.android.ims INSTANT_APP_START_FOREGROUND ignore

   for d in $(adb shell ls -a sdcard); do adb shell touch "sdcard/$d/.metadata_never_index" "sdcard/$d/.noindex" "sdcard/$d/.trackerignore"; done
  #"sdcard/$d/.nomedia"

adb shell setprop debug.threadedOpt 1

adb shell am broadcast -a android.intent.action.ACTION_OPTIMIZE_DEVICE
adb shell am broadcast -a com.android.systemui.action.CLEAR_MEMORY

adb shell pm bg-dexopt-job

adb shell am kill-all
adb shell cmd activity kill-all

printf '%s\n' "All done!"


adb kill-server
rm -rf "${HOME}/.android"
rm -rf "${HOME}/.dbus-keyrings"
