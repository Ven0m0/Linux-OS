#!/usr/bin/env bash
export LC_ALL=C LANG=C

printf '%s\n' "Optimizing"

adb shell cmd shortcut reset-all-throttling
adb shell pm trim-caches 128G
adb shell pm art cleanup
adb shell sm fstrim
adb shell logcat -b all -c
adb shell logcat -c
adb shell sync
adb shell wm density reset
adb shell wm size reset
#adb shell cmd package compile -a  -f --full --secondary-dex -m speed-profile
adb shell cmd package compile -a  -f --full --secondary-dex -m speed
adb shell pm art dexopt-packages -r bg-dexopt

adb shell setprop debug.composition.type dyn
adb shell setprop debug.performance.tuning 1
adb shell setprop debug.fb.rgb565 0
adb shell setprop debug.renderengine.backend skiavk
adb shell setprop debug.hwui.renderer skiavk
adb shell setprop debug.hwui.use_vulkan true
adb shell setprop debug.sf.disable_threaded_present false
adb shell setprop renderthread.skia.reduceopstasksplitting=true
adb shell setprop debug.sf.predict_hwc_composition_strategy 1
adb shell setprop debug.mdpcomp.enable 1
adb shell logcat -G 128K -b main -b system
adb shell logcat -G 64K -b radio -b events -b crash












