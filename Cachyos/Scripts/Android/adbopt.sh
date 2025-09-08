#!/usr/bin/env bash

printf '%s\n' "Setup"
export LC_ALL=C LANG=C

pacman -S android-tools


adb start-server
adb devices
#adb get-state

printf '%s\n' "Cleanup"
adb shell pm art cleanup
adb shell pm trim-caches 128G
adb shell cmd shortcut reset-all-throttling
adb shell logcat -b all -c
adb shell logcat -c
adb shell wm density reset
adb shell wm size reset
adb shell sm fstrim # prob root only
adb shell sync

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



