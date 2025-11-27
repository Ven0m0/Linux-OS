#!/usr/bin/env bash
# Android Toolkit (unified) - device cleaning, optimization, permissions, WhatsApp/media utilities
# Refactored to combine prior scripts: *-clean, *-config, *-whatsapp-manager, device_config_manager
# Style: 2-space indent, bash-native idioms, Arch/Debian friendly, ADB/Shizuku support
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Colors
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MAG=$'\e[35m' CYN=$'\e[36m' RST=$'\e[0m'
has(){ command -v "$1" &>/dev/null; }

# Globals
VERSION="2.0.0"
DRYRUN=0 VERBOSE=0 YES=0 USE_SHIZUKU=0
DEVICE="" JOBS="$(nproc 2>/dev/null || echo 4)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/android-toolkit"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/android-toolkit"
mkdir -p "$CONFIG_DIR" "$CACHE_DIR" &>/dev/null || :

# WhatsApp paths
declare -a WA_OPUS_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio"
  "/sdcard/Music/WhatsApp Audio"
)
declare -a WA_IMG_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images"
  "/sdcard/DCIM/Camera"
  "/sdcard/Pictures"
)
declare -a WA_CLEAN_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp AI Media"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Bug Report Attachments"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Sticker Packs"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Stickers"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Backup Excluded Stickers"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Profile Photos"
)

# Logging
log(){
  local lvl="$1"
  shift
  case "$lvl" in
  info) [[ $VERBOSE -eq 1 ]] && printf '%s[INFO]%s %s\n' "$GRN" "$RST" "$*" ;;
  warn) printf '%s[WARN]%s %s\n' "$YLW" "$RST" "$*" >&2 ;;
  err) printf '%s[ERROR]%s %s\n' "$RED" "$RST" "$*" >&2 ;;
  dbg) [[ $VERBOSE -eq 1 ]] && printf '%s[DBG]%s %s\n' "$BLU" "$RST" "$*" ;;
  esac
}
die(){
  log err "$*"
  exit 1
}
confirm(){
  [[ $YES -eq 1 ]] && return 0
  local p="${1:-Proceed?} [y/N] "
  read -r -p "$p" ans
  [[ ${ans,,} == y* ]]
}

# Device exec helpers
ensure_conn(){
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    has rish || die "rish not found. Install Shizuku and enable CLI."
    rish id &>/dev/null || die "Shizuku not connected."
    log info "Using Shizuku (rish)"
    return 0
  fi
  has adb || die "adb not found. Install Android SDK platform-tools."
  if [[ -n $DEVICE ]]; then
    adb -s "$DEVICE" get-state &>/dev/null || die "Device $DEVICE not connected/authorized."
    ADB=(adb -s "$DEVICE")
  else
    mapfile -t devs < <(adb devices | awk 'NR>1 && $2=="device"{print $1}')
    ((${#devs[@]} == 0)) && die "No adb devices."
    if ((${#devs[@]} > 1)); then
      DEVICE="${devs[0]}"
      log warn "Multiple devices; using: $DEVICE"
      ADB=(adb -s "$DEVICE")
    else
      DEVICE="${devs[0]}"
      ADB=(adb)
    fi
  fi
  log info "Using ADB on: $DEVICE"
}

# Run a remote shell pipeline under sh -lc so pipes/globs work reliably
dev_sh(){
  local cmd="$1"
  if [[ $DRYRUN -eq 1 ]]; then
    log dbg "would: $cmd"
    return 0
  fi
  if [[ $USE_SHIZUKU -eq 1 ]]; then rish sh -lc "$cmd"; else "${ADB[@]}" shell sh -lc "$cmd"; fi
}
# Capture output (trim trailing CR)
dev_out(){
  local cmd="$1" out
  if [[ $DRYRUN -eq 1 ]]; then
    printf '\n'
    return 0
  fi
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    out="$(rish sh -lc "$cmd" 2>/dev/null || :)"
  else out="$("${ADB[@]}" shell sh -lc "$cmd" 2>/dev/null || :)"; fi
  printf '%s\n' "${out//$'\r'/}"
}
# Simple one-liner wrappers
put_setting(){ dev_sh "settings put $1 $2 $3" || :; }
put_config(){ dev_sh "cmd device_config put $1 $2 $3" || :; }
set_prop(){ dev_sh "setprop $1 $2" || :; }

# Utils
free_space(){ dev_out "df -h /data | tail -n1 | awk '{print \$4}'"; }
top_files(){ dev_sh "find /sdcard/Download /sdcard/DCIM -type f -exec ls -la {} \; | sort -k5nr | head -10" || :; }
device_info(){
  local model ver
  model="$(dev_out 'getprop ro.product.model')" ver="$(dev_out 'getprop ro.build.version.release')"
  printf 'Device: %s (Android %s)\n' "$model" "$ver"
}

# CLEANING
clean_app_caches(){
  log info "Clearing app caches..."
  dev_sh "pm list packages -3 | cut -d: -f2 | while read -r p; do pm clear --cache-only \"\$p\" || :; done"
  [[ ${CLEAN_SYSTEM_APPS:-0} -eq 1 ]] && dev_sh "pm list packages -s | cut -d: -f2 | while read -r p; do pm clear --cache-only \"\$p\" || :; done"
  dev_sh "pm trim-caches 128G" || :
}
clean_logs(){
  log info "Clearing logs..."
  dev_sh "logcat -b all -c" || :
  dev_sh "logcat -G 128K -b main -b system; logcat -G 64K -b radio -b events -b crash" || :
  dev_sh "cmd display ab-logging-disable; cmd display dwb-logging-disable; cmd display dmd-logging-disable || :"
  dev_sh "cmd looper_stats disable || :; dumpsys power set_sampling_rate 0 || :" || :
  dev_sh "rm -rf /data/tombstones/* /data/anr/*" || :
}
clean_temp(){
  log info "Removing temp/junk..."
  dev_sh "find /sdcard -type f \\( -iname '*.tmp' -o -iname '*.temp' -o -iname '*.crdownload' -o -iname '*.partial' -o -iname '*.log' -o -iname '*.bak' -o -iname '*.old' -o -iname '~*' -o -iname '.~*' -o -iname 'Thumbs.db' -o -iname '.DS_Store' \\) -delete"
  mapfile -t vols < <(dev_out "ls -1 /storage | grep -Ev '^(self|emulated|\$)'")
  for v in "${vols[@]:-}"; do
    [[ -z $v ]] && continue
    dev_sh "find /storage/$v -type f \\( -iname '*.tmp' -o -iname '*.temp' -o -iname '*.crdownload' -o -iname '*.partial' -o -iname '*.log' -o -iname '*.bak' -o -iname '*.old' -o -iname '~*' -o -iname '.~*' -o -iname 'Thumbs.db' -o -iname '.DS_Store' \\) -delete"
  done
  dev_sh "find /sdcard -type d -empty -delete" || :
  for v in "${vols[@]:-}"; do dev_sh "find /storage/$v -type d -empty -delete" || :; done
}
clean_browser(){
  log info "Clearing browser caches..."
  dev_sh "rm -rf /sdcard/Android/data/com.android.chrome/cache/* /sdcard/Android/data/com.android.browser/cache/* /sdcard/Android/data/com.sec.android.browser/cache/* /sdcard/Android/data/org.mozilla.firefox/cache/* /data/data/org.mozilla.firefox/cache/* /sdcard/Android/data/com.google.android.webview/cache/* /sdcard/Android/data/com.android.webview/cache/*" || :
}
clean_thumbs(){
  log info "Clearing thumbnails..."
  dev_sh "rm -rf /sdcard/DCIM/.thumbnails/* /sdcard/Pictures/.thumbnails/* /sdcard/.thumbnails/* /sdcard/Android/data/com.android.providers.media/albumthumbs/*" || :
  dev_sh "rm -f /sdcard/Android/data/com.android.providers.media/databases/*.db-wal /sdcard/Android/data/com.android.providers.media/databases/*.db-shm" || :
}
clean_downloads(){
  local days="${1:-45}"
  confirm "Delete files in Download older than $days days?" || {
    log warn "skip downloads"
    return 0
  }
  dev_sh "find /sdcard/Download -type f -mtime +$days -delete" || :
}
show_stats(){
  printf '%s\n' "$(device_info)"
  printf 'Free /data: %s\n' "$(free_space)"
  dev_sh "df -h /data" || :
  log info "Top 10 apps by /data usage:"
  dev_sh "du -h /data/data | sort -hr | head -10" || :
  log info "Top 10 largest files (Download/DCIM):"
  top_files || :
}

# OPTIMIZATION CATEGORIES (sane subset, deduped)
opt_art(){
  log info "Optimizing ART..."
  dev_sh "pm bg-dexopt-job --enable || :"
  dev_sh "cmd jobscheduler run -f android \$(cmd jobscheduler list-jobs android | awk '/background-dexopt/{print \$2; exit}')" || :
  dev_sh "cmd package compile -af --full --secondary-dex -m speed-profile || :"
  dev_sh "cmd package compile -a -f --full --secondary-dex -m speed || :"
  dev_sh "pm art dexopt-packages -r bg-dexopt || :"
}
opt_connectivity(){
  log info "Connectivity..."
  put_config connectivity dhcp_rapid_commit_enabled false
  put_setting global data_saver_mode 1
  put_setting global mobile_data_always_on 0
  put_setting global wifi_scan_always_enabled 0
  put_setting global wifi_suspend_optimizations_enabled 2
  dev_sh "cmd netpolicy set restrict-background true" || :
  dev_sh "cmd wifi set-scan-always-available disabled; cmd wifi force-low-latency-mode enabled; cmd wifi force-hi-perf-mode enabled" || :
}
opt_privacy(){
  log info "Privacy..."
  put_setting secure USAGE_METRICS_UPLOAD_ENABLED 0
  put_setting secure limit_ad_tracking 1
  put_setting global media.metrics.enabled 0
  put_setting global package_usage_stats_enabled 0
}
opt_battery(){
  log info "Battery..."
  local c="vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,fullbackup_deferred=true,keyvaluebackup_deferred=true,gps_mode=low_power,data_saver=true,optional_sensors_disabled=true,advertiser_id_enabled=false"
  put_setting global battery_saver_constants "$c"
  put_setting global dynamic_power_savings_enabled 1
  put_setting global cached_apps_freezer enabled
  dev_sh "cmd power set-adaptive-power-saver-enabled true" || :
}
opt_graphics(){
  log info "Graphics/UI..."
  put_setting global force_gpu_rendering 1
  put_setting global disable_hw_overlays 1
  put_setting global debug.hwui.use_disable_overdraw 1
  put_config graphics render_thread_priority high
  put_config graphics enable_cpu_boost true
  put_config graphics enable_gpu_boost true
  put_config systemui window_cornerRadius 0
  put_config systemui window_blur 0
  dev_sh "cmd display ab-logging-disable; cmd display dwb-logging-disable; wm disable-blur true || :" || :
}
opt_webview(){
  log info "WebView/ANGLE..."
  dev_sh "echo 'webview --enable-features=DeferImplInvalidation,ScrollUpdateOptimizations' > /data/local/tmp/webview-command-line; chmod 0644 /data/local/tmp/webview-command-line" || :
  dev_sh "cmd webviewupdate set-webview-implementation com.android.webview.beta" || :
  put_setting global angle_gl_driver_all_angle 1
  put_setting global angle_gl_driver_selection_values angle
}
opt_audio(){
  log info "Audio..."
  put_setting global audio.deep_buffer.media true
  put_setting global audio.offload.video true
  put_setting global audio.offload.track.enable true
  put_setting global media.stagefright.thumbnail.prefer_hw_codecs true
}
opt_input(){
  log info "Input/animations..."
  put_setting secure long_press_timeout 250
  put_setting secure multi_press_timeout 250
  put_setting global animator_duration_scale 0.0
  put_setting global transition_animation_scale 0.0
  put_setting global window_animation_scale 0.0
}
opt_system(){
  log info "System..."
  put_config activity_manager use_compaction true
  put_config activity_manager enable_background_cpu_boost true
  put_config activity_manager force_high_refresh_rate true
  dev_sh "cmd uimode night yes || :" || :
  dev_sh "logcat -G 128K -b main -b system; logcat -G 64K -b radio -b events -b crash" || :
}
opt_doze(){
  log info "Doze/App standby..."
  dev_sh "cmd deviceidle force-idle; cmd deviceidle unforce; dumpsys deviceidle whitelist +com.android.systemui" || :
}

apply_profile(){
  local prof="${1:-balanced}"
  case "$prof" in
  performance)
    opt_system
    opt_graphics
    opt_input
    opt_art
    ;;
  battery)
    opt_battery
    opt_doze
    opt_privacy
    put_setting global animator_duration_scale 0.5
    put_setting global transition_animation_scale 0.5
    put_setting global window_animation_scale 0.5
    ;;
  balanced | *)
    opt_system
    opt_graphics
    opt_battery
    opt_art
    put_setting global animator_duration_scale 0.3
    put_setting global transition_animation_scale 0.3
    put_setting global window_animation_scale 0.3
    ;;
  esac
}

# PERMISSIONS (from TOML [permission])
grant_perm(){
  local mode="$1" pkg="$2"
  case "$mode" in
  dump) dev_sh "pm grant \"$pkg\" android.permission.DUMP" || : ;;
  write) dev_sh "pm grant \"$pkg\" android.permission.WRITE_SECURE_SETTINGS" || : ;;
  doze) dev_sh "dumpsys deviceidle whitelist +\"$pkg\"" || : ;;
  *)
    log warn "unknown perm: $mode"
    return 1
    ;;
  esac
}
apply_permissions_from_toml(){
  [[ -f "$CONFIG_FILE" ]] || {
    log warn "config not found: $CONFIG_FILE"
    return 1
  }
  local in=0 line key vals
  while IFS= read -r line; do
    [[ -z $line || $line =~ ^[[:space:]]*# ]] && continue
    if [[ $line =~ ^\[([^]]+)\]$ ]]; then
      in=$([[ ${BASH_REMATCH[1]} == permission ]] && echo 1 || echo 0)
      continue
    fi
    [[ $in -eq 0 ]] && continue
    if [[ $line =~ ^([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      key="${BASH_REMATCH[1]}"
      vals="${BASH_REMATCH[2]}"
      vals="${vals// /}"
      IFS=',' read -r -a arr <<< "$vals"
      for m in "${arr[@]}"; do grant_perm "$m" "$key"; done
    fi
  done < "$CONFIG_FILE"
  log info "permissions applied"
}

# WHATSAPP
wa_clean_opus(){
  local days="${1:-90}"
  log info "WA: delete .opus older than $days days"
  for p in "${WA_OPUS_PATHS[@]}"; do dev_sh "find \"$p\" -type f -name '*.opus' -mtime +$days -delete" || :; done
}
wa_clean_paths(){
  log info "WA: purge specific folders"
  for p in "${WA_CLEAN_PATHS[@]}"; do dev_sh "rm -rf \"$p\"/*" || :; done
}
wa_opt_images(){
  [[ "${WA_OPTIMIZE_IMAGES:-1}" -eq 1 ]] || {
    log warn "WA image optimization disabled"
    return 0
  }
  log info "WA: dedupe/optimize images (if tools available in Termux)"
  # Use Termux tools if installed on-device
  local tools=(/data/data/com.termux/files/usr/bin/{fclones,rimage,flaca,compresscli,imgc})
  for base in "${WA_IMG_PATHS[@]}"; do
    # dedupe
    if dev_sh "[[ -x ${tools[0]} ]]"; then
      dev_sh "${tools[0]} group -r \"$base\" --threads $JOBS && ${tools[0]} dedupe --strategy=oldestrandom \"$base\"" || :
    fi
    # optimize
    if dev_sh "[[ -x ${tools[1]} ]]"; then
      dev_sh "find \"$base\" -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \\) -exec ${tools[1]} -i {} -o {} \\;" || :
    elif dev_sh "[[ -x ${tools[2]} ]]"; then
      dev_sh "find \"$base\" -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \\) -exec ${tools[2]} {} \\;" || :
    elif dev_sh "[[ -x ${tools[3]} ]]"; then
      dev_sh "find \"$base\" -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \\) -exec ${tools[3]} {} \\;" || :
    elif dev_sh "[[ -x ${tools[4]} ]]"; then
      dev_sh "find \"$base\" -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \\) -exec ${tools[4]} {} \\;" || :
    else
      log warn "No image optimization tools found on device"
    fi
  done
}

# DEVICE CONFIG apply/reset (wrapper)
device_config_apply(){
  log info "Apply device_config (subset)"
  opt_connectivity
  opt_privacy
  opt_battery
  opt_graphics
  opt_system
}
device_config_reset(){
  log warn "Reset device_config namespaces to defaults"
  local ns=(connectivity privacy runtime runtime_native runtime_native_boot systemui activity_manager package_manager_service window_manager wifi bluetooth adservices graphics)
  for s in "${ns[@]}"; do dev_sh "cmd device_config reset \"$s\"" || :; done
}

# BACKUP/RESTORE
pkg_backup(){
  local out="${1:-pkglist-$(date +%Y%m%d).txt}"
  dev_out "pm list packages | cut -d: -f2" > "$out"
  printf 'Saved to %s\n' "$out"
}
pkg_restore(){
  local file="$1"
  [[ -f $file ]] || die "restore file missing: $file"
  while IFS= read -r p; do
    [[ -z $p ]] && continue
    dev_sh "pm install \"$p\"" || log warn "install failed: $p"
  done < "$file"
}

# COMMANDS
cmd_info(){
  ensure_conn
  device_info
}
cmd_stats(){
  ensure_conn
  show_stats
}
cmd_clean(){
  local sys=0 dl_days=0 no_browser=0 no_thumbs=0
  while [[ $# -gt 0 ]]; do case "$1" in
    --system-apps)
      sys=1
      shift
      ;;
    --downloads)
      dl_days="${2:-0}"
      shift 2
      ;;
    --no-browser)
      no_browser=1
      shift
      ;;
    --no-thumbnails)
      no_thumbs=1
      shift
      ;;
    -h | --help)
      usage_clean
      return 0
      ;;
    *)
      log err "unknown: $1"
      usage_clean
      return 1
      ;;
    esac done
  ensure_conn
  export CLEAN_SYSTEM_APPS=$sys
  local before after
  before="$(free_space)"
  log info "Cleanup start. Free /data: $before"
  clean_app_caches
  clean_logs
  clean_temp
  [[ $no_browser -eq 0 ]] && clean_browser
  [[ $no_thumbs -eq 0 ]] && clean_thumbs
  ((dl_days > 0)) && clean_downloads "$dl_days"
  after="$(free_space)"
  printf 'Free /data: %s -> %s\n' "$before" "$after"
}
cmd_optimize(){
  local prof="" dns="" cats=()
  while [[ $# -gt 0 ]]; do case "$1" in
    --profile | -p)
      prof="$2"
      shift 2
      ;;
    --dns)
      dns="$2"
      shift 2
      ;;
    art | connectivity | privacy | battery | graphics | audio | input | webview | system | doze | all)
      cats+=("$1")
      shift
      ;;
    -h | --help)
      usage_opt
      return 0
      ;;
    *)
      log err "unknown: $1"
      usage_opt
      return 1
      ;;
    esac done
  ensure_conn
  [[ -n $dns ]] && {
    put_setting global private_dns_mode hostname
    put_setting global private_dns_specifier "$dns"
  }
  if [[ -n $prof ]]; then
    apply_profile "$prof"
    log info "profile applied: $prof"
    return 0
  fi
  ((${#cats[@]} == 0)) && cats=(all)
  log info "Optimize: ${cats[*]}"
  for c in "${cats[@]}"; do
    case "$c" in
    art) opt_art ;;
    connectivity) opt_connectivity ;;
    privacy) opt_privacy ;;
    battery) opt_battery ;;
    graphics) opt_graphics ;;
    audio) opt_audio ;;
    input) opt_input ;;
    webview) opt_webview ;;
    system) opt_system ;;
    doze) opt_doze ;;
    all)
      opt_art
      opt_connectivity
      opt_privacy
      opt_battery
      opt_graphics
      opt_audio
      opt_input
      opt_webview
      opt_system
      opt_doze
      ;;
    esac
  done
}
cmd_permissions(){
  local action="apply" pkg="" perm=""
  while [[ $# -gt 0 ]]; do case "$1" in
    list | add | apply | grant)
      action="$1"
      shift
      ;;
    -h | --help)
      usage_perm
      return 0
      ;;
    *) if [[ -z $pkg ]]; then
      pkg="$1"
      shift
    elif [[ -z $perm ]]; then
      perm="$1"
      shift
    else
      log err "too many args"
      usage_perm
      return 1
    fi ;;
    esac done
  ensure_conn
  case "$action" in
  list)
    [[ -f $CONFIG_FILE ]] || die "no config: $CONFIG_FILE"
    awk '/^\[permission\]/{p=1;next} /^\[/{p=0} p && !/^[[:space:]]*#/{print}' "$CONFIG_FILE"
    ;;
  add)
    [[ -n $pkg && -n $perm ]] || {
      usage_perm
      return 1
    }
    if [[ ! -f "$CONFIG_FILE" ]]; then
      cat > "$CONFIG_FILE" <<EOF
# Android Toolkit Configuration
[permission]
# package.name=dump,write,doze

[compilation]
# package.name=PRIORITY_INTERACTIVE_FAST:speed-profile
EOF
    fi
    grep -q '^\[permission\]' "$CONFIG_FILE" || printf '\n[permission]\n' >> "$CONFIG_FILE"
    if grep -q "^$pkg=" "$CONFIG_FILE"; then
      sed -i "s|^$pkg=.*|$pkg=$perm|" "$CONFIG_FILE"
    else
      printf '%s=%s\n' "$pkg" "$perm" >> "$CONFIG_FILE"
    fi
    log info "added: $pkg -> $perm"
    ;;
  apply) apply_permissions_from_toml ;;
  grant)
    [[ -n $pkg && -n $perm ]] || {
      usage_perm
      return 1
    }
    IFS=',' read -r -a arr <<< "$perm"
    for m in "${arr[@]}"; do grant_perm "$m" "$pkg"; done
    ;;
  esac
}
cmd_whatsapp(){
  local days=90 no_images=0
  while [[ $# -gt 0 ]]; do case "$1" in
    --days | -d)
      days="$2"
      shift 2
      ;;
    --no-images)
      no_images=1
      shift
      ;;
    -h | --help)
      usage_wa
      return 0
      ;;
    *)
      log err "unknown: $1"
      usage_wa
      return 1
      ;;
    esac done
  ensure_conn
  local before after
  before="$(free_space)"
  wa_clean_opus "$days"
  wa_clean_paths
  [[ $no_images -eq 0 ]] && WA_OPTIMIZE_IMAGES=1 wa_opt_images
  after="$(free_space)"
  printf 'Free /data: %s -> %s\n' "$before" "$after"
}
cmd_backup(){
  ensure_conn
  pkg_backup "${1:-}"
}
cmd_restore(){
  ensure_conn
  [[ $# -gt 0 ]] || die "restore needs a file"
  pkg_restore "$1"
}
cmd_devcfg(){
  ensure_conn
  case "${1:-apply}" in apply) device_config_apply ;; reset) device_config_reset ;; *)
    usage_devcfg
    return 1
    ;;
  esac
}

# USAGE
usage(){
  cat <<EOF
Android Toolkit v$VERSION
Usage: ${0##*/} [global opts] <command> [args]

Global:
  -n, --dry-run       no changes
  -v, --verbose       verbose logs
  -s, --shizuku       use Shizuku (rish)
  -y, --yes           auto-confirm
  -j, --jobs N        parallel jobs (default: $JOBS)
  -D, --device ID     adb device id
  -h, --help          this help
  --version           show version

Commands:
  info                show device info
  stats               storage/app/file stats
  clean [opts]        clean caches/logs/tmp/downloads
  optimize [cats...]  apply optimizations (or --profile P)
  permissions [...]   manage/apply app permissions via TOML
  whatsapp [opts]     cleanup+optimize WA media
  backup [FILE]       backup package list
  restore FILE        restore packages (attempt pm install)
  device-config [apply|reset]  apply/reset device_config subset

Run: ${0##*/} <cmd> --help  for command details
EOF
}
usage_clean(){
  cat <<EOF
clean options:
  --system-apps         clean system app caches too
  --downloads DAYS      delete Download files older than DAYS
  --no-browser          skip browser cache
  --no-thumbnails       skip thumbnail cleanup
EOF
}
usage_opt(){
  cat <<EOF
optimize:
  Categories: art connectivity privacy battery graphics audio input webview system doze all
  --profile, -p P      performance | battery | balanced
  --dns HOST           set private DNS
EOF
}
usage_perm(){
  cat <<EOF
permissions:
  list | add PKG PERMS | apply | grant PKG PERMS
  PERMS: comma-separated of: dump,write,doze
EOF
}
usage_wa(){
  cat <<EOF
whatsapp:
  --days, -d N         delete .opus older than N (default 90)
  --no-images          skip image optimization
EOF
}
usage_devcfg(){ echo "device-config: apply | reset"; }

# MAIN
main(){
  [[ $# -eq 0 ]] && {
    usage
    exit 0
  }
  while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
    -n | --dry-run)
      DRYRUN=1
      shift
      ;;
    -v | --verbose)
      VERBOSE=1
      shift
      ;;
    -s | --shizuku)
      USE_SHIZUKU=1
      shift
      ;;
    -y | --yes)
      YES=1
      shift
      ;;
    -j | --jobs)
      JOBS="$2"
      shift 2
      ;;
    -D | --device)
      DEVICE="$2"
      shift 2
      ;;
    --version)
      echo "$VERSION"
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) break ;;
    esac
  done
  local cmd="${1:-}"
  shift || :
  case "$cmd" in
  info) cmd_info "$@" ;;
  stats) cmd_stats "$@" ;;
  clean) cmd_clean "$@" ;;
  optimize) cmd_optimize "$@" ;;
  permissions) cmd_permissions "$@" ;;
  whatsapp) cmd_whatsapp "$@" ;;
  backup) cmd_backup "$@" ;;
  restore) cmd_restore "$@" ;;
  device-config) cmd_devcfg "$@" ;;
  help | -h | --help) usage ;;
  *)
    log err "unknown command: $cmd"
    usage
    exit 1
    ;;
  esac
}
main "$@"
