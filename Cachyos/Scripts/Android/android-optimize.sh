#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
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
    [[ -n $adb_cmd ]] || {
      err "rish not available; install Shizuku"
      return 1
    }
    return 0
  fi

  "$adb_cmd" start-server &>/dev/null || :
  "$adb_cmd" get-state &>/dev/null || {
    err "No device connected; enable USB debugging"
    return 1
  }
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

# === Package Manager Detection ===
pm_detect(){
  if has paru; then
    printf 'paru'
    return
  fi
  if has yay; then
    printf 'yay'
    return
  fi
  if has pacman; then
    printf 'pacman'
    return
  fi
  if has apt; then
    printf 'apt'
    return
  fi
  if has pkg && ((IS_TERMUX)); then
    printf 'pkg'
    return
  fi
  printf ''
}

# === Confirmation Prompt ===
confirm(){
  local prompt="${1:-Continue? }"
  local reply

  while :; do
    read -rp "$prompt [y/N] " reply
    case "${reply,,}" in
      y | yes) return 0 ;;
      n | no | "") return 1 ;;
      *) warn "Please answer y or n" ;;
    esac
  done
}

# === File Operations ===
file_size(){
  stat -c "%s" "$1" 2>/dev/null || stat -f "%z" "$1" 2>/dev/null || echo 0
}

human_size(){
  local bytes="$1" scale=0
  local -a units=("B" "KB" "MB" "GB" "TB")

  while ((bytes > 1024 && scale < 4)); do
    bytes=$((bytes / 1024))
    ((scale++))
  done

  printf "%d %s" "$bytes" "${units[$scale]}"
}

# === Cleanup Trap Helpers ===
cleanup_workdir(){
  [[ -n ${WORKDIR:-} && -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR" || :
}

cleanup_mount(){
  [[ -n ${MNT_PT:-} ]] && mountpoint -q -- "$MNT_PT" && umount -R "$MNT_PT" || :
}

cleanup_loop(){
  [[ -n ${LOOP_DEV:-} && -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" || :
}

setup_cleanup(){
  trap 'cleanup_workdir; cleanup_mount; cleanup_loop' EXIT
  trap 'err "failed at line ${LINENO}"' ERR
}

# === Find Tools with Fallbacks ===
FD="${FD:-$(hasname fd fdfind || :)}"
RG="${RG:-$(hasname rg grep || :)}"
BAT="${BAT:-$(hasname bat batcat cat || :)}"
SD="${SD:-$(hasname sd || :)}"
readonly FD RG BAT SD

# === Script Configuration ===
readonly VERSION="3.0.0"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/android-toolkit"
readonly CONFIG_FILE="${CONFIG_DIR}/config.toml"

ADB_CMD="$(detect_adb || :)"
export ADB_CMD

readonly SPEED_APPS=(
  com.whatsapp com.snapchat.android com.instagram.android com.zhiliaoapp.musically
  app.revanced.android.youtube anddea.youtube. music com.spotify.music
  com.feelingtouch.rtd app.revenge com.supercell.clashroyale
  com.pittvandewitt.wavelet com.freestylelibre3. app.de
  com.nothing.camera com.android.htmlviewer com.android.providers.media
)
readonly SYSTEM_APPS=(
  com. android.systemui com.nothing.launcher com.android.internal.systemui. navbar. threebutton
  com.google.android.webview com.google.android.webview.beta com.google.android.inputmethod.latin
  com.android.providers.settings com.android.server.telecom com.android.location.fused
  com.mediatek.location. lppe. main com.google.android.permissioncontroller com.android.bluetooth
)

# Aliases for compatibility
info(){ log "$1"; }
ok(){ msg "$1"; }

# AAPT2 android.jar locator
aapt2_jar(){
  local roots=("${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" /opt/android-sdk)
  for r in "${roots[@]}"; do
    [[ -d "$r/platforms" ]] || continue
    local jar=""
    while IFS= read -r -d '' c; do
      [[ -f "$c/android.jar" ]] && jar="$c/android.jar"
    done < <(find "$r/platforms" -maxdepth 1 -type d -name "android-*" -print0 2>/dev/null || :)
    [[ -n $jar ]] && {
      printf '%s' "$jar"
      return
    }
  done
}

# === Android device tasks ===
task_maint(){
  sec "Maintenance"
  ash << 'EOF'
sync
cmd stats write-to-disk
settings put global fstrim_mandatory_interval 1
pm art cleanup
pm trim-caches 256G
cmd shortcut reset-all-throttling
logcat -b all -c
wm density reset
wm size reset
sm fstrim
cmd activity idle-maintenance
cmd system_update
cmd otadexopt cleanup
EOF
}

task_cleanup_fs(){
  sec "Filesystem cleanup"
  ash 'find /sdcard /storage/emulated/0 -type f -iregex ".*\.\(log\|bak\|old\|tmp\)$" -delete 2>/dev/null || :'
}

task_art(){
  sec "ART optimize"
  local jid
  jid="$(ash 'cmd jobscheduler list-jobs android 2>/dev/null' | grep -F background-dexopt | awk '{print $2}' || :)"

  ash << EOF
$([[ -n $jid ]] && echo "cmd jobscheduler run -f android $jid")
cmd package compile -af --full -r cmdline -m speed
cmd package compile -a --full -r cmdline -m speed-profile
pm art dexopt-packages -r bg-dexopt
art pr-deopt-job --run
pm bg-dexopt-job
EOF
}

task_block(){
  sec "Firewall"
  [[ $1 == enable ]] && ash 'cmd connectivity set-chain3-enabled true'
  [[ $1 == disable ]] && ash 'cmd connectivity set-chain3-enabled false'
  [[ $1 == block ]] && ash "cmd connectivity set-package-networking-enabled false \"$2\""
  [[ $1 == unblock ]] && ash "cmd connectivity set-package-networking-enabled true \"$2\""
}

task_perf(){
  sec "Performance tweaks"
  ash << 'EOF'
setprop debug.performance. tuning 1
setprop debug.mdpcomp.enable 1
device_config put graphics enable_cpu_boost true
device_config put graphics enable_gpu_boost true
device_config put graphics render_thread_priority high
device_config put activity_manager force_high_refresh_rate true
device_config put activity_manager enable_background_cpu_boost true
device_config put activity_manager use_compaction true
device_config put privacy location_access_check_enabled false
device_config put privacy location_accuracy_enabled false
EOF
}

task_render(){
  sec "Rendering tweaks"
  ash << 'EOF'
setprop debug. composition.type dyn
setprop debug.fb.rgb565 0
setprop debug.sf.predict_hwc_composition_strategy 1
setprop debug. hwui.use_buffer_age true
setprop debug.sf.gpu_comp_tiling 1
setprop debug.enable. sglscale 1
setprop debug.sf.use_phase_offsets_as_durations 1
setprop debug.sf.enable_gl_backpressure 1
setprop debug.egl.hw 1
setprop debug.sf.hw 1
setprop debug.gfx.driver 1
setprop debug.enabletr true
setprop debug.hwui.renderer_mode 1
settings put global force_gpu_rendering 1
settings put global disable_hw_overlays 1
settings put global gpu_rasterization_forced 1
EOF
}

task_audio(){
  sec "Audio tweaks"
  ash << 'EOF'
settings put global audio. offload. video true
settings put global audio.offload.track. enable true
settings put global audio.offload.gapless. enabled true
settings put global audio.offload.multiple. enabled true
settings put global media.stagefright.thumbnail.prefer_hw_codecs true
EOF
}

task_battery(){
  sec "Battery tweaks"
  ash << 'EOF'
settings put global dynamic_power_savings_enabled 1
settings put global adaptive_battery_management_enabled 0
settings put global app_auto_restriction_enabled 1
settings put global cached_apps_freezer enabled
cmd power suppress-ambient-display true
cmd power set-fixed-performance-mode-enabled false
cmd power set-adaptive-power-saver-enabled true
EOF
}

task_input(){
  sec "Input/animations"
  ash << 'EOF'
settings put global animator_duration_scale 0.0
settings put global transition_animation_scale 0.0
settings put global window_animation_scale 0.0
wm disable-blur true
EOF
}

task_net(){
  sec "Network tweaks"
  ash << 'EOF'
cmd netpolicy set restrict-background true
settings put global data_saver_mode 1
settings put global mobile_data_always_on 0
settings put global wifi_scan_always_enabled 0
settings put global ble_scan_always_enabled 0
settings put global network_avoid_bad_wifi 1
EOF
}

task_webview(){
  sec "WebView/ANGLE"
  ash << 'EOF'
cmd webviewupdate set-webview-implementation com.android.webview.beta
settings put global angle_gl_driver_all_angle 1
settings put global angle_debug_package com.android.angle
settings put global angle_gl_driver_selection_values angle
settings put global angle_gl_driver_selection_pkgs com.android.webview,com.android.webview.beta
EOF
}

task_misc(){
  sec "Misc tweaks"
  ash << 'EOF'
setprop debug.debuggerd.disable 1
settings put secure USAGE_METRICS_UPLOAD_ENABLED 0
settings put system send_security_reports 0
device_config put systemui window_shadow 0
device_config put systemui window_blur 0
EOF
}

task_experimental(){
  sec "Experimental Tweaks (Aggressive)"
  confirm "These are aggressive experimental tweaks.  Proceed?" || return 0

  ash << 'EOF'
device_config put runtime_native_boot pin_camera false
device_config put launcher ENABLE_QUICK_LAUNCH_V2 true
device_config put activity_manager set_sync_disabled_for_tests persistent
device_config put surfaceflinger set_max_frame_rate_multiplier 0. 5
cmd power set-fixed-performance-mode-enabled true
cmd power set-mode 0
cmd thermalservice override-status 1
cmd looper_stats disable
cmd display ab-logging-disable
cmd display dwb-logging-disable
settings put global window_animation_scale 0.25
settings put global transition_animation_scale 0.25
settings put global animator_duration_scale 0.0
settings put global GPUTURBO_SWITCH 1
settings put global GPUTUNER_SWITCH 1
settings put global game_driver_all_apps 1
settings put global updatable_driver_all_apps 1
settings put global ram_expand_size_list 1
settings put global fstrim_mandatory_interval 1
EOF
  ok "Experimental tweaks applied"
}

task_compile_speed(){
  sec "High-perf apps → speed"
  local batch=""
  for p in "${SPEED_APPS[@]}"; do
    batch+="cmd package compile -f --full -r cmdline -m speed $p"$'\n'
  done
  ash <<< "$batch"
}

task_compile_system(){
  sec "System apps → everything"
  local batch=""
  for p in "${SYSTEM_APPS[@]}"; do
    batch+="cmd package compile -f --full -r cmdline -m everything $p"$'\n'
  done
  ash <<< "$batch"
}

task_finalize(){
  sec "Finalize"
  ash << 'EOF'
am broadcast -a android.intent.action.ACTION_OPTIMIZE_DEVICE
am broadcast -a com.android.systemui.action. CLEAR_MEMORY
am kill-all
cmd activity kill-all
dumpsys batterystats --reset
EOF
}

task_permissions_toml(){
  sec "Applying permissions from TOML"
  [[ -f $CONFIG_FILE ]] || {
    warn "Config not found: $CONFIG_FILE"
    return
  }

  local in=0 line key vals batch=""
  while IFS= read -r line; do
    [[ -z $line || $line =~ ^[[:space:]]*# ]] && continue
    if [[ $line =~ ^\[([^]]+)\]$ ]]; then
      in=$([[ ${BASH_REMATCH[1]} == permission ]] && echo 1 || echo 0)
      continue
    fi
    [[ $in -eq 0 ]] && continue

    if [[ $line =~ ^([^=[:space:]]+)[[:space:]]*=[[:space:]]*(. +)$ ]]; then
      key="${BASH_REMATCH[1]}"
      vals="${BASH_REMATCH[2]}"
      vals="${vals// /}"
      IFS=',' read -r -a arr <<< "$vals"
      for m in "${arr[@]}"; do
        case "$m" in
          dump) batch+="pm grant \"$key\" android.permission.DUMP"$'\n' ;;
          write) batch+="pm grant \"$key\" android.permission.WRITE_SECURE_SETTINGS"$'\n' ;;
          doze) batch+="dumpsys deviceidle whitelist +\"$key\""$'\n' ;;
        esac
      done
    fi
  done < "$CONFIG_FILE"

  [[ -n $batch ]] && ash <<< "$batch"
  ok "Permissions applied"
}

cmd_device_all(){
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
  task_permissions_toml
  task_finalize
  ok "Device optimization complete"
}

cmd_monolith(){
  device_ok || return 1
  local mode="${1:-everything-profile}"
  sec "Monolith compile ($mode)"
  ash "cmd package compile -a --full -r cmdline -m \"$mode\""
  ok "Compilation complete"
}

cmd_cache_clean(){
  device_ok || return 1
  sec "Clear app caches"
  if ((IS_TERMUX)); then
    ash 'pm list packages -3' | cut -d: -f2 | xargs -r -n1 -P"$NPROC" -I{} ash "pm clear --cache-only {}" &>/dev/null || :
    ash 'pm list packages -s' | cut -d: -f2 | xargs -r -n1 -P"$NPROC" -I{} ash "pm clear --cache-only {}" &>/dev/null || :
  else
    local adb_cmd
    adb_cmd="${ADB_CMD:-$(detect_adb)}"
    "$adb_cmd" shell 'pm list packages -3' 2>/dev/null | cut -d: -f2 |
      xargs -r -n1 -P"$NPROC" -I{} "$adb_cmd" shell pm clear --cache-only {} &>/dev/null || :
    "$adb_cmd" shell 'pm list packages -s' 2>/dev/null | cut -d: -f2 |
      xargs -r -n1 -P"$NPROC" -I{} "$adb_cmd" shell pm clear --cache-only {} &>/dev/null || :
  fi
  ash 'pm trim-caches 128G'
  ash 'logcat -b all -c'
  ok "Cache cleared"
}

cmd_index_nomedia(){
  local base="${1:-/storage/emulated/0}"
  sec "Index guard (. nomedia)"
  while IFS= read -r -d '' d; do
    : > "$d/.nomedia" 2>/dev/null || :
    : > "$d/.noindex" 2>/dev/null || :
    : > "$d/.metadata_never_index" 2>/dev/null || :
    : > "$d/.trackerignore" 2>/dev/null || :
  done < <(find "$base" -type d -readable -print0 2>/dev/null || :)
  ok "Index guards created"
}

cmd_wa_clean(){
  local wa_base="${1:-/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media}"
  sec "WhatsApp cleanup"
  [[ -d $wa_base ]] || {
    warn "Not found: $wa_base"
    return
  }

  local b a
  b="$(du -sm "$wa_base" 2>/dev/null | cut -f1 || printf 0)"
  find "$wa_base" -type f -iregex '.*\.\(jpg\|jpeg\|png\|gif\|mp4\|mov\|wmv\|flv\|webm\|mxf\|avi\|avchd\|mkv\|opus\)$' -mtime +45 -delete 2>/dev/null || :

  rm -rf "$wa_base/WhatsApp AI Media"/* \
    "$wa_base/WhatsApp Bug Report Attachments"/* \
    "$wa_base/WhatsApp Stickers"/* 2>/dev/null || :

  a="$(du -sm "$wa_base" 2>/dev/null | cut -f1 || printf 0)"
  ok "Freed $((b - a)) MB"

  if ((IS_TERMUX)); then
    if command -v oxipng &>/dev/null || command -v jpegoptim &>/dev/null; then
      sec "Optimizing Images (WhatsApp)"
      find "$wa_base" -type f -name "*.jpg" -exec jpegoptim --strip-all {} + 2>/dev/null || :
      find "$wa_base" -type f -name "*.png" -exec oxipng -o 2 -i 0 --strip safe {} + 2>/dev/null || :
      ok "Images optimized"
    fi
  fi
}

cmd_aapt2_opt(){
  local in="${1:-target/release/app-unsigned. apk}"
  local out="${2:-target/release/app-optimized.apk}"
  sec "AAPT2 optimize"
  command -v aapt2 &>/dev/null || {
    err "aapt2 not found"
    return 1
  }
  local jar
  jar="$(aapt2_jar)"
  [[ -f $jar ]] || {
    err "android. jar not found"
    return 1
  }
  mkdir -p "${out%/*}"
  aapt2 compile --dir res -o compiled-res.zip &>/dev/null || :
  aapt2 link -o linked-res.apk -I "$jar" --manifest AndroidManifest.xml --java gen compiled-res.zip &>/dev/null || :
  aapt2 optimize --collapse-resource-names --shorten-resource-paths --enable-sparse-encoding -o "$out" "$in"
  ok "Saved → $out"
}

# === Termux-specific tasks ===
task_pkg_maint(){
  sec "Package maintenance"
  info "Updating packages..."
  pkg update -y || err "Update failed"
  pkg upgrade -y || err "Upgrade failed"
  info "Cleaning..."
  pkg clean -y
  pkg autoclean -y
  apt-get autoremove -y &>/dev/null || :
  ok "Packages updated"
}

task_cache_termux(){
  sec "Cache cleanup"
  local cleaned=()
  command -v uv &>/dev/null && {
    uv cache clean --force &>/dev/null
    uv cache prune &>/dev/null
    cleaned+=(uv)
  }
  command -v pip &>/dev/null && {
    pip cache purge &>/dev/null
    cleaned+=(pip)
  }
  [[ -d "$HOME/.npm" ]] && {
    npm cache clean --force &>/dev/null
    cleaned+=(npm)
  }
  [[ -d "$HOME/.cache" ]] && {
    find "$HOME/.cache" -mindepth 1 -delete 2>/dev/null || :
    cleaned+=(user-cache)
  }
  [[ -d /data/data/com.termux/files/usr/tmp ]] && {
    find /data/data/com.termux/files/usr/tmp -mindepth 1 -delete 2>/dev/null || :
    cleaned+=(termux-tmp)
  }
  ok "Cleaned: ${cleaned[*]:-none}"
}

task_fs_hygiene(){
  sec "Filesystem hygiene"
  local ed ef cnt=0
  ed="$(find "$HOME" -type d -empty 2>/dev/null || :)"
  [[ -n $ed ]] && { printf '%s\n' "$ed" | xargs -r rm -r && ((cnt++)); }
  ef="$(find "$HOME" -type f -empty 2>/dev/null || :)"
  [[ -n $ef ]] && { printf '%s\n' "$ef" | xargs -r rm && ((cnt++)); }
  ((cnt > 0)) && ok "Removed empty dirs/files" || info "No empty dirs/files"
}

task_large_files(){
  local mb="${1:-100}"
  local path="${2:-$HOME}"
  sec "Large files (>${mb}MB)"
  info "Searching $path..."
  local lf
  if [[ -n $FD ]]; then
    lf="$("$FD" . "$path" -t f -S "+${mb}M" -x du -h {} + 2>/dev/null | sort -rh || :)"
  else
    lf="$(find "$path" -type f -size "+${mb}M" -exec du -h {} + 2>/dev/null | sort -rh || :)"
  fi
  [[ -n $lf ]] && {
    ok "Found:"
    printf '%s\n' "$lf"
  } || info "None found"
}

task_updatedb(){
  sec "Update locate DB"
  command -v updatedb &>/dev/null || {
    warn "Install: pkg install findutils"
    return
  }
  info "Indexing..."
  updatedb
  ok "DB updated"
}

cmd_termux_full(){
  task_pkg_maint
  task_cache_termux
  task_fs_hygiene
  task_updatedb
  ok "Termux optimization complete"
}

# === Interactive menu ===
menu(){
  printf '\n%s%s=== Android Optimizer v%s ===%s\n' "$MGN" "$BLD" "$VERSION" "$DEF"
  if ((IS_TERMUX)); then
    cat << 'EOF'
[Device] (requires rish/Shizuku)
1) Full device optimize (Standard)
2) Experimental Tweaks (Aggressive)
3) Monolith compile [mode]
4) Clear app caches
5) Create index guards [path]
6) WhatsApp cleanup [path]
[Termux]
7) Full Termux optimize
8) Package maintenance
9) Cache cleanup
10) Filesystem hygiene
11) Find large files [MB] [path]
u) Update locate DB
[Other]
a) AAPT2 optimize [in] [out]
q) Quit
EOF
  else
    cat << 'EOF'
1) Full device optimize (ADB)
2) Experimental Tweaks (Aggressive)
3) Monolith compile [mode]
4) Clear app caches
5) Create index guards [path]
6) WhatsApp cleanup [path]
7) AAPT2 optimize [in] [out]
[Termux Utils]
8) Package maintenance
9) Cache cleanup
10) Filesystem hygiene
11) Find large files [MB] [path]
u) Update locate DB
q) Quit
EOF
  fi
}

interactive(){
  while :; do
    menu
    read -rp "Select: " c args
    case "$c" in
      1) cmd_device_all ;;
      2) device_ok && task_experimental ;;
      3) cmd_monolith "$args" ;;
      4) cmd_cache_clean ;;
      5) cmd_index_nomedia "$args" ;;
      6) cmd_wa_clean "$args" ;;
      7) ((IS_TERMUX)) && cmd_termux_full || cmd_aapt2_opt "$args" ;;
      8) task_pkg_maint ;;
      9) task_cache_termux ;;
      10) task_fs_hygiene ;;
      11) task_large_files "$args" ;;
      u) task_updatedb ;;
      a) ((IS_TERMUX)) && cmd_aapt2_opt "$args" || : ;;
      q | Q) break ;;
      *) warn "Invalid" ;;
    esac
  done
  info "Done"
}

usage(){
  cat << EOF
android-optimize. sh v$VERSION - Unified Android optimizer (ADB or Termux+Shizuku)

Device commands:
  device-all              Full device optimization (Standard)
  experimental            Apply aggressive experimental tweaks
  monolith [mode]         Compile all apps (default: everything-profile)
  cache-clean             Clear app caches
  index-nomedia [path]    Create . nomedia guards (default: /storage/emulated/0)
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
Termux device access: $([[ $IS_TERMUX -eq 1 && -n ${RISH:-} ]] && printf "rish (Shizuku)" || printf "N/A")
EOF
}

main(){
  local cmd="${1:-menu}"
  shift || :
  case "$cmd" in
    device-all) cmd_device_all ;;
    experimental) device_ok && task_experimental ;;
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
