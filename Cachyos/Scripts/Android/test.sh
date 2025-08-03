

echo -e "Optimizing ..."
adb shell cmd shortcut reset-all-throttling
adb shell pm trim-caches 999999M
adb shell pm compile -a -f --check-prof false -m speed
adb shell pm compile -a -f --check-prof false --compile-layouts
adb shell pm bg-dexopt-job
adb shell pm trim-caches 999999M
adb shell rm -rf /data/anr/*
adb shell rm -rf /data/crashdata/*
adb shell rm -rf /data/dalvik-cache/*
adb shell rm -rf /data/local/*
adb shell rm -rf /data/log/*
adb shell rm -rf /data/resource-cache/*
adb shell rm -rf /data/tombstones/*
adb shell sm fstrim

adb shell settings put global wifi_scan_always_enabled 0
adb shell settings put global ble_scan_always_enabled 0
adb shell settings put global mobile_data_always_on 0
adb shell settings put global enhanced_processing 1
adb shell settings put global sem_enhanced_cpu_responsiveness 1
adb shell settings put global game_driver_all_apps 1
adb shell settings put global wifi.supplicant_scan_interval 180\
adb shell settings put secure upload_debug_log_pref 0
adb shell settings put secure upload_log_pref 0
adb shell settings put global sys_traced 0
adb shell settings put global wifi_verbose_logging_enabled 0
adb shell settings put global send_action_app_error 0
adb shell settings put global foreground_service_starts_logging_enabled 0
adb shell settings put global enable_diskstats_logging 0
adb shell settings put global activity_starts_logging_enabled 0
adb shell settings put secure upload_debug_log_pref 0
adb shell settings put secure upload_log_pref 0
adb shell settings put global sys_traced 0
adb shell settings put global wifi_verbose_logging_enabled 0
adb shell settings put global send_action_app_error 0
adb shell settings put global foreground_service_starts_logging_enabled 0
adb shell settings put global enable_diskstats_logging 0
adb shell settings put global activity_starts_logging_enabled 0
adb shell settings put global profiler.force_disable_err_rpt 1
adb shell settings put global profiler.force_disable_ulog 1
adb shell settings put global profiler.debugmonitor false
adb shell settings put global profiler.launch false
adb shell settings put global logcat.live disable
adb shell settings put system rakuten_denwa 0
adb shell settings put system send_security_reports 0
adb shell settings put system remote_control 0
adb shell settings put system dk_log_level 0
adb shell settings put system user_log_enabled 0
adb shell settings put system window_orientation_listener_log 0
adb shell settings put system multicore_packet_scheduler 1

# https://github.com/Sushkyn/adbthings
#setprop: adb shell setprop var value
adb shell setprop debug.bt.lowspeed true
adb shell settings put global audio.offload.video true
adb shell settings put global audio.offload.gapless.enabled true
adb shell settings put global media.stagefright.thumbnail.prefer_hw_codecs true
adb shell setprop debug.sqlite.syncmode 1
adb shell setprop debug.hwui.force_dark true
adb shell setprop debug.performance.tuning 1
adb shell setprop debug.gralloc.enable_fb_ubwc 1
adb shell setprop debug.hwui.level 0
adb shell setprop debug.hwui.render_dirty_regions false
adb shell setprop debug.hwui.show_dirty_regions false
adb shell setprop debug.composition.type gpu
adb shell setprop debug.cpurend.vsync true
adb shell setprop debug.enabletr true
adb shell setprop debug.sf.ddms 0
adb shell setprop debug.sf.hw 1
adb shell setprop debug.sf.enable_hwc_vds 1
adb shell setprop debug.sf.swaprect 1
adb shell setprop debug.egl.hw 1
adb shell setprop debug.egl.profiler 1
adb shell setprop debug.overlayui.enable 1
adb shell setprop debug.sf.enable_gl_backpressure 1
adb shell setprop debug.sf.latch_unsignaled 1
adb shell setprop debug.sf.recomputecrop 0
adb shell setprop debug.enable.sglscale 1
