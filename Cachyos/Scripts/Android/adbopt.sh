#!/usr/bin/env bash

# https://github.com/vaginessa/adb-cheatsheet
adb shell sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.api

printf '%s\n' "Setup"
export LC_ALL=C LANG=C

pacman -S 
if ! command -v adb &>/dev/null; then
  if command -v pacman &>/dev/null; then
    pacman -Qq android-tools &>/dev/null || sudo pacman -Sq --noconfirm --noprogressbar --needed android-tools
  elif command -v apt-get; then
if ; then
  echo "installed"
else
  echo "not installed"
fi

pkg_installed(){
  local pkg=$1
  if command -v pacman &>/dev/null; then
    pacman -Qq "$pkg" &>/dev/null
  elif command -v dpkg-query &>/dev/null; then
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"
  else
    return 2
  fi
}

adb start-server
adb devices

printf '%s\n' "Cleanup"
adb shell sync
adb shell cmd stats write-to-disk
adb shell pm art cleanup
adb shell pm trim-caches 128G
adb shell cmd shortcut reset-all-throttling
adb shell logcat -b all -c
adb shell logcat -c
adb shell wm density reset
adb shell wm size reset
adb shell sm fstrim # prob root only

printf '%s\n' "Optimizing ART..."
# Run any postponed dex‐opt jobs immediately 
adb shell cmd jobscheduler run -f android \
  $(adb shell cmd jobscheduler list-jobs android \
  | grep background-dexopt | awk '{print $2}')

# Does it twice to force speed-profile for all and does only speed for apps that might benefit without overwriting
adb shell cmd package compile -af --full --secondary-dex -m speed-profile
adb shell cmd package compile -a  -f --full --secondary-dex -m speed
adb shell pm art dexopt-packages -r bg-dexopt


printf '%s\n' "General rendering tweaks..."
adb shell setprop debug.composition.type dyn
adb shell setprop debug.fb.rgb565 0
adb shell setprop debug.sf.disable_threaded_present false
adb shell setprop renderthread.skia.reduceopstasksplitting true
adb shell setprop debug.sf.predict_hwc_composition_strategy 1
adb shell setprop debug.hwui.use_buffer_age true
adb shell setprop debug.hwui.render_dirty_regions true
adb shell settings put global force_gpu_rendering 1
adb shell settings put global debug.hwui.force_gpu_command_drawing 1
adb shell settings put global debug.hwui.use_disable_overdraw 1

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

printf '%s\n' "Logs..."
adb shell logcat -G 128K -b main -b system
adb shell logcat -G 64K -b radio -b events -b crash

printf '%s\n' "Performance tweaks..."
adb shell setprop debug.performance.tuning 1
adb shell setprop debug.mdpcomp.enable 1

printf '%s\n' "Battery tweaks..."
adb shell cmd power suppress-ambient-display true
adb shell cmd power set-face-down-detector false
# adb shell cmd power set-mode 1/0
adb shell cmd power set-fixed-performance-mode-enabled false
# adb shell cmd power set-fixed-performance-mode-enabled true/false
adb shell cmd power set-adaptive-power-saver-enabled true
# adb shell cmd power set-adaptive-power-saver-enabled true/false
adb shell settings put system accelerometer_rotation 0

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
adb shell cmd system_update
adb shell cmd otadexopt cleanup

# Improve scroll responsiveness apparently
gfx_set(){ adb shell cmd gfxinfo "$1" reset && adb shell cmd gfxinfo "$1" framestats; }



# Aggressive AppStandby / Doze toggles
adb shell cmd deviceidle force-idle
adb shell cmd deviceidle unforce
doze_app(){ adb shell cmd deviceidle whitelist +"$1"; }

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



#pm list packages
# List disabled packages
adb shell pm list packages -d
# Filter to only show enabled packages
adb shell pm list packages -e
# Filter to only show third party packages
adb shell pm list packages -3
# Set the default home activity (aka launcher)
#adb shell cmd package set-home-activity [--user USER_ID] TARGET-COMPONENT

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

# Print data in .db files, clean:
grep -vx -f <(sqlite3 Main.db .dump) <(sqlite3 ${DB} .schema) 
# Use below command fr update dg.db file:
sqlite3 /data/data/com.google.android.gms/databases/dg.db "update main set c='0' where a like '%attest%';" 

WSS_set(){ adb shellpm grant "$1" android.permission.WRITE_SECURE_SETTINGS }





