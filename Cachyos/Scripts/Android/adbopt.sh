#!/usr/bin/env bash

# https://github.com/vaginessa/adb-cheatsheet


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
#adb get-state

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

printf '%s\n' "Optimizing ART"
# Does it twice to force speed-profile for all and does only speed for apps that might benefit without overwriting
adb shell cmd package compile -af --full --secondary-dex -m speed-profile
adb shell cmd package compile -a  -f --full --secondary-dex -m speed
adb shell pm art dexopt-packages -r bg-dexopt

printf '%s\n' "General rendering"
adb shell setprop debug.composition.type dyn
adb shell setprop debug.fb.rgb565 0
adb shell setprop debug.sf.disable_threaded_present false
adb shell setprop renderthread.skia.reduceopstasksplitting true
adb shell setprop debug.sf.predict_hwc_composition_strategy 1
adb shell settings set global force_gpu_rendering 1
adb shell setprop debug.hwui.render_dirty_regions true

printf '%s\n' "Vulkan"
adb shell setprop debug.renderengine.backend skiavk
adb shell setprop debug.hwui.renderer skiavk # or 'skiagl'
adb shell setprop debug.hwui.use_vulkan true

printf '%s\n' "Logs"
adb shell logcat -G 128K -b main -b system
adb shell logcat -G 64K -b radio -b events -b crash

printf '%s\n' "Performance"
adb shell setprop debug.performance.tuning 1
adb shell setprop debug.mdpcomp.enable 1


printf '%s\n' "Other"
adb shell cmd uimode night yes 
adb shell cmd uimode car no
adb shell cmd -w wifi force-country-code enabled DE
adb shell cmd -w wifi force-low-latency-mode enabled
adb shell cmd wifi force-low-latency-mode enabled
adb shell cmd -w wifi force-hi-perf-mode enabled
adb shell cmd wifi force-hi-perf-mode enabled
# Sets the interval between RSSI polls to milliseconds.
#adb shell cmd -w wifi set-poll-rssi-interval-msecs <int>

#pm list packages
# List disabled packages
pm list packages -d
# Filter to only show enabled packages
pm list packages -e
# Filter to only show third party packages
pm list packages -3
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
# am start -a android.intent.action.VIEW \
# Open settings:
 am start -n com.android.settings/com.android.settings.Settings
# Start prefered webbrowser:
am start -a android.intent.action.VIEW -d <url> (com.android.browser | com.android.chrome | com.sec.android.sbrowser)
# Open any URL in default browser
am start -a android.intent.action.VIEW -d <url>
# Print Activities:
am start -a com.android.settings/.wifi.CaptivePortalWebViewActivity

# Auto rotation off
content insert –uri content://settings/system –bind name:s:accelerometer_rotation –bind value:i:0
# Rotate portrait
content insert –uri content://settings/system –bind name:s:user_rotation –bind value:i:0

# Adopting USB-Drive
sm set-force-adoptable true

# Print data in .db files, clean:
grep -vx -f <(sqlite3 Main.db .dump) <(sqlite3 ${DB} .schema) 
# Use below command fr update dg.db file:
sqlite3 /data/data/com.google.android.gms/databases/dg.db "update main set c='0' where a like '%attest%';" 







