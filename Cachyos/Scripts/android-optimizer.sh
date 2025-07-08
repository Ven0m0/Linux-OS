#!/bin/bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C LANG=C
shopt -s nullglob globstar

adb start-server
adb shell setprop debug.enabletr 1
adb shell setprop debug.sf.hw 1
adb shell setprop debug.egl.hw 1
adb shell setprop debug.performance.tuning 1
adb shell setprop debug.composition.type c2d
adb shell setprop debug.renderengine.backend skiaglthreaded
adb shell setprop debug.hwui.renderer skiagl
adb shell setprop debug.fb.rgb565 0
adb shell setprop debug.egl.profiler 0
adb shell setprop debug.debuggerd.disable 1
adb shell setprop debug.tracing.screen_state 0
adb shell setprop debug.tracing.mnc 0
adb shell setprop debug.sf.enable_egl_image_tracker 0
adb shell setprop debug.mdpcomp.logs 0
adb shell setprop debug.mdpcomp.enable 1
adb shell setprop debug.enable_dmabuf 1
adb shell setprop debug.sf.predict_hwc_composition_strategy 1
adb shell setprop debug.hwui.use_buffer_age true
adb shell pm art cleanup
adb shell pm trim-caches 999999999999999999

adb shell cmd package compile -a -f --full --secondary-dex -m speed-profile

adb shell cmd package compile -f --full --secondary-dex -m speed com.feelingtouch.rtd
adb shell cmd package compile -f --full --secondary-dex -m speed com.supercell.clashroyale
adb shell cmd package compile -f --full --secondary-dex -m speed app.revanced.android.youtube
adb shell cmd package compile -f --full --secondary-dex -m speed com.spotify.music
adb shell cmd package compile -f --full --secondary-dex -m speed com.zhiliaoapp.musically
adb shell cmd package compile -f --full --secondary-dex -m speed com.snapchat.android
adb shell cmd package compile -f --full --secondary-dex -m speed app.revenge
adb shell cmd package compile -f --full --secondary-dex -m speed com.instagram.android

adb shell cmd package compile -f --full --secondary-dex -m everything com.nothing.launcher
adb shell cmd package compile -f --full --secondary-dex -m speed com.google.android.webview.beta
adb shell cmd package compile -f --full --secondary-dex -m speed com.google.android.inputmethod.latin

adb shell cmd package compile -f --full --secondary-dex -m everything com.android.systemui
adb shell cmd package compile -f --full --secondary-dex -m everything com.android.internal.systemui.navbar.threebutton
adb shell cmd package compile -f --full --secondary-dex -m everything com.android.providers.settings
adb shell cmd package compile -f --full --secondary-dex -m everything com.android.server.telecom
adb shell cmd package compile -f --full --secondary-dex -m everything com.mediatek.location.lppe.main
adb shell cmd package compile -f --full --secondary-dex -m everything com.android.location.fused
adb shell cmd package compile -f --full --secondary-dex -m everything com.google.android.permissioncontroller
adb shell cmd package compile -f --full --secondary-dex -m everything com.android.bluetooth

adb shell cmd package compile -f --full --secondary-dex -m speed com.pittvandewitt.wavelet
adb shell cmd package compile -f --full --secondary-dex -m speed com.freestylelibre3.app.de
adb shell cmd package compile -f --full --secondary-dex -m speed com.whatsapp
adb shell cmd package compile -f --full --secondary-dex -m speed com.android.htmlviewer
adb shell cmd package compile -f --full --secondary-dex -m speed com.nothing.camera
adb shell cmd package compile -f --full --secondary-dex -m speed com.android.providers.media

adb shell pm art dexopt-packages -r bg-dexopt
adb shell pm art cleanup
adb shell pm trim-caches 999999999999999999
adb shell pm trim-caches 999999999999999999
adb shell pm trim-caches 999999999999999999
adb kill-server
