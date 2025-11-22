#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Unified Android optimizer: desktop+ADB or Termux+Shizuku
# Device optimization, ART compilation, cache cleanup, filesystem maintenance

readonly IS_TERMUX="$([[ -d /data/data/com.termux/files ]] && echo 1 || echo 0)"
readonly NPROC="$(nproc 2> /dev/null || echo 4)"

# Tool resolution with caching
ADB="${ADB:-adb}"
FD="${FD:-$(command -v fd || command -v fdfind || :)}"
RG="${RG:-$(command -v rga || command -v rg || :)}"
SD="${SD:-$(command -v sd || :)}"

# Shizuku/rish detection for Termux
if ((IS_TERMUX)); then
  RISH="$(command -v rish || :)"
  [[ -n "$RISH" ]] && ADB="$RISH" || warn "rish not found; device tasks unavailable"
fi

readonly SPEED_APPS=(
  com.whatsapp com.snapchat.android com.instagram.android com.zhiliaoapp.musically
  app.revanced.android.youtube anddea.youtube.music com.spotify.music
  com.feelingtouch.rtd app.revenge com.supercell.clashroyale
  com.pittvandewitt.wavelet com.freestylelibre3.app.de
  com.nothing.camera com.android.htmlviewer com.android.providers.media
)
readonly SYSTEM_APPS=(
  com.android.systemui com.nothing.launcher com.android.internal.systemui.navbar.threebutton
  com.google.android.webview com.google.android.webview.beta com.google.android.inputmethod.latin
  com.android.providers.settings com.android.server.telecom com.android.location.fused
  com.mediatek.location.lppe.main com.google.android.permissioncontroller com.android.bluetooth
)

# Color setup
C_RST="$(tput sgr0 2> /dev/null || :)"
C_BLD="$(tput bold 2> /dev/null || :)"
C_RED="$(tput setaf 1 2> /dev/null || :)"
C_GRN="$(tput setaf 2 2> /dev/null || :)"
C_YLW="$(tput setaf 3 2> /dev/null || :)"
C_BLU="$(tput setaf 4 2> /dev/null || :)"
C_MAG="$(tput setaf 5 2> /dev/null || :)"

log() { printf '%s%s[%s]%s %s\n' "${2:-}" "$C_BLD" "$1" "$C_RST" "$3"; }
info() { log '*' "$C_BLU" "$1"; }
ok() { log '+' "$C_GRN" "$1"; }
warn() { log '!' "$C_YLW" "$1" >&2; }
err() { log '-' "$C_RED" "$1" >&2; }
sec() { printf '\n%s%s=== %s ===%s\n' "$C_MAG" "$C_BLD" "$*" "$C_RST"; }

confirm() {
  local p="${1:-Continue?}"
  while :; do
    read -rp "$p [y/N] " r
    case "${r,,}" in y | yes) return 0 ;; n | no | "") return 1 ;; *) warn "y/n only" ;; esac
  done
}

# Shell executor: local or ADB/rish
ash() {
  if ((IS_TERMUX)); then
    [[ -n "$RISH" ]] && "$RISH" "$@" 2> /dev/null || eval "$*"
  else
    "$ADB" shell "$@" 2> /dev/null || :
  fi
}

# Validate device access
device_ok() {
  if ((IS_TERMUX)); then
    [[ -n "$RISH" ]] || {
      err "rish not available; install Shizuku"
      return 1
    }
    return 0
  fi
  command -v "$ADB" &> /dev/null || {
    err "adb not found"
    return 1
  }
  "$ADB" start-server &> /dev/null || :
  "$ADB" get-state &> /dev/null || {
    err "No device; enable USB debugging"
    return 1
  }
}

# AAPT2 android.jar locator
aapt2_jar() {
  local roots=("${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" /opt/android-sdk)
  for r in "${roots[@]}"; do
    [[ -d "$r/platforms" ]] || continue
    local jar=""
    while IFS= read -r -d '' c; do
      [[ -f "$c/android.jar" ]] && jar="$c/android.jar"
    done < <(find "$r/platforms" -maxdepth 1 -type d -name "android-*" -print0 2> /dev/null || :)
    [[ -n "$jar" ]] && {
      printf '%s' "$jar"
      return
    }
  done
}

# === Android device tasks ===
task_maint() {
  sec "Maintenance"
  ash sync
  ash cmd stats write-to-disk
  ash settings put global fstrim_mandatory_interval 1
  ash pm art cleanup
  ash pm trim-caches 256G
  ash cmd shortcut reset-all-throttling
  ash logcat -b all -c
  ash wm density reset
  ash wm size reset
  ash sm fstrim
  ash cmd activity idle-maintenance
  ash cmd system_update
  ash cmd otadexopt cleanup
}

task_cleanup_fs() {
  sec "Filesystem cleanup"
  ash 'find /sdcard /storage/emulated/0 -type f -iregex ".*\.\(log\|bak\|old\|tmp\)$" -delete 2>/dev/null || :'
}

task_art() {
  sec "ART optimize"
  local jid
  jid="$(ash cmd jobscheduler list-jobs android 2> /dev/null | grep -F background-dexopt | awk '{print $2}' || :)"
  [[ -n "$jid" ]] && ash cmd jobscheduler run -f android "$jid"
  ash cmd package compile -af --full -r cmdline -m speed
  ash cmd package compile -a --full -r cmdline -m speed-profile
  ash pm art dexopt-packages -r bg-dexopt
  ash art pr-deopt-job --run
  ash pm bg-dexopt-job
}
task_block() {
  sec "Firewalll"
  [[ "$1" == enable ]] && ash cmd connectivity set-chain3-enabled true
  [[ "$1" == disable ]] && ash cmd connectivity set-chain3-enabled false
  [[ "$1" == block ]] && ash cmd connectivity set-package-networking-enabled false "$2"
  [[ "$1" == unblock ]] && ash cmd connectivity set-package-networking-enabled true "$2"
}

task_perf() {
  sec "Performance tweaks"
  ash setprop debug.performance.tuning 1
  ash setprop debug.mdpcomp.enable 1
  ash device_config put graphics enable_cpu_boost true
  ash device_config put graphics enable_gpu_boost true
  ash device_config put graphics render_thread_priority high
  ash device_config put activity_manager force_high_refresh_rate true
  ash device_config put activity_manager enable_background_cpu_boost true
  ash device_config put activity_manager use_compaction true
  ash device_config put privacy location_access_check_enabled false
  ash device_config put privacy location_accuracy_enabled false
}

task_render() {
  sec "Rendering tweaks"
  ash setprop debug.composition.type dyn
  ash setprop debug.fb.rgb565 0
  ash setprop debug.sf.predict_hwc_composition_strategy 1
  ash setprop debug.hwui.use_buffer_age true
  ash setprop debug.sf.gpu_comp_tiling 1
  ash setprop debug.enable.sglscale 1
  ash setprop debug.sf.use_phase_offsets_as_durations 1
  ash setprop debug.sf.enable_gl_backpressure 1
  ash setprop debug.egl.hw 1
  ash setprop debug.sf.hw 1
  ash setprop debug.gfx.driver 1
  ash setprop debug.enabletr true
  ash setprop debug.hwui.renderer_mode 1
  ash settings put global force_gpu_rendering 1
  ash settings put global disable_hw_overlays 1
  ash settings put global gpu_rasterization_forced 1
}

task_audio() {
  sec "Audio tweaks"
  ash settings put global audio.offload.video true
  ash settings put global audio.offload.track.enable true
  ash settings put global audio.offload.gapless.enabled true
  ash settings put global audio.offload.multiple.enabled true
  ash settings put global media.stagefright.thumbnail.prefer_hw_codecs true
}

task_battery() {
  sec "Battery tweaks"
  ash settings put global dynamic_power_savings_enabled 1
  ash settings put global adaptive_battery_management_enabled 0
  ash settings put global app_auto_restriction_enabled 1
  ash settings put global cached_apps_freezer enabled
  ash cmd power suppress-ambient-display true
  ash cmd power set-fixed-performance-mode-enabled false
  ash cmd power set-adaptive-power-saver-enabled true
}

task_input() {
  sec "Input/animations"
  ash settings put global animator_duration_scale 0.0
  ash settings put global transition_animation_scale 0.0
  ash settings put global window_animation_scale 0.0
  ash wm disable-blur true
}

task_net() {
  sec "Network tweaks"
  ash cmd netpolicy set restrict-background true
  ash settings put global data_saver_mode 1
  ash settings put global mobile_data_always_on 0
  ash settings put global wifi_scan_always_enabled 0
  ash settings put global ble_scan_always_enabled 0
  ash settings put global network_avoid_bad_wifi 1
}

task_webview() {
  sec "WebView/ANGLE"
  ash cmd webviewupdate set-webview-implementation com.android.webview.beta
  ash settings put global angle_gl_driver_all_angle 1
  ash settings put global angle_debug_package com.android.angle
  ash settings put global angle_gl_driver_selection_values angle
  ash settings put global angle_gl_driver_selection_pkgs com.android.webview,com.android.webview.beta
}

task_misc() {
  sec "Misc tweaks"
  ash setprop debug.debuggerd.disable 1
  ash settings put secure USAGE_METRICS_UPLOAD_ENABLED 0
  ash settings put system send_security_reports 0
  ash device_config put systemui window_shadow 0
  ash device_config put systemui window_blur 0
}

task_compile_speed() {
  sec "High-perf apps → speed"
  for p in "${SPEED_APPS[@]}"; do
    info "$p"
    ash cmd package compile -f --full -r cmdline -m speed "$p"
  done
}

task_compile_system() {
  sec "System apps → everything"
  for p in "${SYSTEM_APPS[@]}"; do
    info "$p"
    ash cmd package compile -f --full -r cmdline -m everything "$p"
  done
}

task_finalize() {
  sec "Finalize"
  ash am broadcast -a android.intent.action.ACTION_OPTIMIZE_DEVICE
  ash am broadcast -a com.android.systemui.action.CLEAR_MEMORY
  ash am kill-all
  ash cmd activity kill-all
  ash dumpsys batterystats --reset
}

# Full device optimization
cmd_device_all() {
  device_ok || return 1
  task_maint
  task_cleanup_fs
  task_art
  task_perf
  task_render
  task_audio
  task_battery
  task_input
  task_net
  task_webview
  task_misc
  task_compile_speed
  task_compile_system
  task_finalize
  ok "Device optimization complete"
}

# Monolith compile
cmd_monolith() {
  device_ok || return 1
  local mode="${1:-everything-profile}"
  sec "Monolith compile ($mode)"
  ash cmd package compile -a --full -r cmdline -m "$mode"
  ok "Compilation complete"
}

# Cache cleanup
cmd_cache_clean() {
  device_ok || return 1
  sec "Clear app caches"
  if ((IS_TERMUX)); then
    ash pm list packages -3 | cut -d: -f2 | xargs -r -n1 -P"$NPROC" ash pm clear --cache-only &> /dev/null || :
    ash pm list packages -s | cut -d: -f2 | xargs -r -n1 -P"$NPROC" ash pm clear --cache-only &> /dev/null || :
  else
    "$ADB" shell pm list packages -3 2> /dev/null | cut -d: -f2 \
      | xargs -r -n1 -P"$NPROC" -I{} "$ADB" shell pm clear --cache-only {} &> /dev/null || :
    "$ADB" shell pm list packages -s 2> /dev/null | cut -d: -f2 \
      | xargs -r -n1 -P"$NPROC" -I{} "$ADB" shell pm clear --cache-only {} &> /dev/null || :
  fi
  ash pm trim-caches 128G
  ash logcat -b all -c
  ok "Cache cleared"
}

# Index guard creation
cmd_index_nomedia() {
  local base="${1:-/storage/emulated/0}"
  sec "Index guard (.nomedia)"
  while IFS= read -r -d '' d; do
    : > "$d/.nomedia" 2> /dev/null || :
    : > "$d/.noindex" 2> /dev/null || :
    : > "$d/.metadata_never_index" 2> /dev/null || :
    : > "$d/.trackerignore" 2> /dev/null || :
  done < <(find "$base" -type d -readable -print0 2> /dev/null || :)
  ok "Index guards created"
}

# WhatsApp cleanup
cmd_wa_clean() {
  local wa="${1:-/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media}"
  sec "WhatsApp cleanup (>45d)"
  [[ -d "$wa" ]] || {
    warn "Not found: $wa"
    return
  }
  local b a
  b="$(du -sm "$wa" 2> /dev/null | cut -f1 || printf 0)"
  find "$wa" -type f -iregex '.*\.\(jpg\|jpeg\|png\|gif\|mp4\|mov\|wmv\|flv\|webm\|mxf\|avi\|avchd\|mkv\)$' -mtime +45 -delete 2> /dev/null || :
  a="$(du -sm "$wa" 2> /dev/null | cut -f1 || printf 0)"
  ok "Freed $((b - a)) MB"
}

# AAPT2 optimization
cmd_aapt2_opt() {
  local in="${1:-target/release/app-unsigned.apk}"
  local out="${2:-target/release/app-optimized.apk}"
  sec "AAPT2 optimize"
  command -v aapt2 &> /dev/null || {
    err "aapt2 not found"
    return 1
  }
  local jar
  jar="$(aapt2_jar)"
  [[ -f "$jar" ]] || {
    err "android.jar not found"
    return 1
  }
  mkdir -p "$(dirname "$out")"
  aapt2 compile --dir res -o compiled-res.zip &> /dev/null || :
  aapt2 link -o linked-res.apk -I "$jar" --manifest AndroidManifest.xml --java gen compiled-res.zip &> /dev/null || :
  aapt2 optimize --collapse-resource-names --shorten-resource-paths --enable-sparse-encoding -o "$out" "$in"
  ok "Saved → $out"
}

# === Termux-specific tasks ===
task_pkg_maint() {
  sec "Package maintenance"
  info "Updating packages..."
  pkg update -y || err "Update failed"
  pkg upgrade -y || err "Upgrade failed"
  info "Cleaning..."
  pkg clean -y
  pkg autoclean -y
  apt-get autoremove -y &> /dev/null || :
  ok "Packages updated"
}

task_cache_termux() {
  sec "Cache cleanup"
  local cleaned=()
  command -v uv &> /dev/null && {
    uv cache clean --force &> /dev/null
    uv cache prune &> /dev/null
    cleaned+=(uv)
  }
  command -v pip &> /dev/null && {
    pip cache purge &> /dev/null
    cleaned+=(pip)
  }
  [[ -d "$HOME/.npm" ]] && {
    npm cache clean --force &> /dev/null
    cleaned+=(npm)
  }
  [[ -d "$HOME/.cache" ]] && {
    find "$HOME/.cache" -mindepth 1 -delete 2> /dev/null || :
    cleaned+=(user-cache)
  }
  [[ -d /data/data/com.termux/files/usr/tmp ]] && {
    find /data/data/com.termux/files/usr/tmp -mindepth 1 -delete 2> /dev/null || :
    cleaned+=(termux-tmp)
  }
  ok "Cleaned: ${cleaned[*]:-none}"
}

task_fs_hygiene() {
  sec "Filesystem hygiene"
  local ed ef cnt=0
  ed="$(find "$HOME" -type d -empty 2> /dev/null || :)"
  [[ -n "$ed" ]] && { printf '%s\n' "$ed" | xargs -r rm -r && ((cnt++)); }
  ef="$(find "$HOME" -type f -empty 2> /dev/null || :)"
  [[ -n "$ef" ]] && { printf '%s\n' "$ef" | xargs -r rm && ((cnt++)); }
  ((cnt > 0)) && ok "Removed empty dirs/files" || info "No empty dirs/files"
}

task_large_files() {
  local mb="${1:-100}"
  local path="${2:-$HOME}"
  sec "Large files (>${mb}MB)"
  info "Searching $path..."
  local lf
  if [[ -n "$FD" ]]; then
    lf="$("$FD" . "$path" -t f -S "+${mb}M" -x du -h {} + 2> /dev/null | sort -rh || :)"
  else
    lf="$(find "$path" -type f -size "+${mb}M" -exec du -h {} + 2> /dev/null | sort -rh || :)"
  fi
  [[ -n "$lf" ]] && {
    ok "Found:"
    printf '%s\n' "$lf"
  } || info "None found"
}

task_updatedb() {
  sec "Update locate DB"
  command -v updatedb &> /dev/null || {
    warn "Install: pkg install findutils"
    return
  }
  info "Indexing..."
  updatedb
  ok "DB updated"
}

# Full Termux optimization
cmd_termux_full() {
  task_pkg_maint
  task_cache_termux
  task_fs_hygiene
  task_updatedb
  ok "Termux optimization complete"
}

# === Interactive menu ===
menu() {
  printf '\n%s%s=== Android Optimizer ===%s\n' "$C_MAG" "$C_BLD" "$C_RST"
  if ((IS_TERMUX)); then
    cat << EOF
[Device] (requires rish/Shizuku)
1) Full device optimize
2) Monolith compile [mode]
3) Clear app caches
4) Create index guards [path]
5) WhatsApp cleanup [path]
[Termux]
6) Full Termux optimize
7) Package maintenance
8) Cache cleanup
9) Filesystem hygiene
0) Find large files [MB] [path]
u) Update locate DB
[Other]
a) AAPT2 optimize [in] [out]
q) Quit
EOF
  else
    cat << EOF
1) Full device optimize (ADB)
2) Monolith compile [mode]
3) Clear app caches
4) Create index guards [path]
5) WhatsApp cleanup [path]
6) AAPT2 optimize [in] [out]
7) Package maintenance (Termux)
8) Cache cleanup (Termux)
9) Filesystem hygiene (Termux)
0) Find large files [MB] [path]
u) Update locate DB (Termux)
q) Quit
EOF
  fi
}

interactive() {
  while :; do
    menu
    read -rp "Select: " c args
    case "$c" in
    1) cmd_device_all ;;
    2) cmd_monolith $args ;;
    3) cmd_cache_clean ;;
    4) cmd_index_nomedia $args ;;
    5) cmd_wa_clean $args ;;
    6) ((IS_TERMUX)) && cmd_termux_full || cmd_aapt2_opt $args ;;
    7) ((IS_TERMUX)) && task_pkg_maint || task_pkg_maint ;;
    8) ((IS_TERMUX)) && task_cache_termux || task_cache_termux ;;
    9) ((IS_TERMUX)) && task_fs_hygiene || task_fs_hygiene ;;
    0) task_large_files $args ;;
    u) task_updatedb ;;
    a) ((IS_TERMUX)) && cmd_aapt2_opt $args || : ;;
    q | Q) break ;;
    *) warn "Invalid" ;;
    esac
  done
  info "Done"
}

usage() {
  cat << EOF
android-optimize.sh - Unified Android optimizer (ADB or Termux+Shizuku)

Device commands:
  device-all              Full device optimization
  monolith [mode]         Compile all apps (default: everything-profile)
  cache-clean             Clear app caches
  index-nomedia [path]    Create .nomedia guards (default: /storage/emulated/0)
  wa-clean [path]         WhatsApp media cleanup >45d
  aapt2-opt [in] [out]    Optimize APK with AAPT2

Termux commands:
  termux-full             Full Termux optimization
  pkg-maint               Package maintenance
  cache-termux            Cache cleanup (uv, pip, npm, user)
  fs-hygiene              Remove empty files/dirs
  large-files [MB] [path] Find large files (default: 100MB, \$HOME)
  updatedb                Update locate database

Interactive:
  menu                    Show interactive menu (default)

Environment: $([[ $IS_TERMUX -eq 1 ]] && printf "Termux" || printf "Desktop+ADB")
Termux device access: $([[ $IS_TERMUX -eq 1 && -n "${RISH:-}" ]] && printf "rish (Shizuku)" || printf "N/A")
EOF
}

main() {
  local cmd="${1:-menu}"
  shift || :
  case "$cmd" in
  device-all) cmd_device_all ;;
  monolith) cmd_monolith "$@" ;;
  cache-clean) cmd_cache_clean ;;
  index-nomedia) cmd_index_nomedia "$@" ;;
  wa-clean) cmd_wa_clean "$@" ;;
  aapt2-opt) cmd_aapt2_opt "$@" ;;
  termux-full) cmd_termux_full ;;
  pkg-maint) task_pkg_maint ;;
  cache-termux) task_cache_termux ;;
  fs-hygiene) task_fs_hygiene ;;
  large-files) task_large_files "$@" ;;
  updatedb) task_updatedb ;;
  menu) interactive ;;
  -h | --help | help) usage ;;
  *)
    err "Unknown: $cmd"
    usage
    exit 2
    ;;
  esac
}
main "$@"
