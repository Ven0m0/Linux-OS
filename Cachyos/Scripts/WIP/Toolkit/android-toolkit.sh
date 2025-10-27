#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'; shopt -s nullglob globstar
export LC_ALL=C LANG=C

# --- Configuration ---
DRYRUN=0             # Set to 1 for dry-run mode (no actual changes)
VERBOSE=0            # Set to 1 for verbose output
USE_SHIZUKU=0        # Set to 1 to use Shizuku instead of ADB
JOBS=$(nproc 2>/dev/null || echo 4)  # Parallel jobs
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/android-toolkit"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/android-toolkit"

# --- WhatsApp Media Paths ---
WHATSAPP_OPUS_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio"
  "/sdcard/Music/WhatsApp Audio"
)

WHATSAPP_IMAGE_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images"
  "/sdcard/DCIM/Camera"
  "/sdcard/Pictures"
)

WHATSAPP_CLEAN_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp AI Media"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Bug Report Attachments" 
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Sticker Packs"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Stickers"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Backup Excluded Stickers"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Profile Photos"
)

# --- Helper functions ---
has(){ command -v "$1" &>/dev/null; }

log(){
  local level="$1"; shift
  case "$level" in
    info)  [[ $VERBOSE -eq 1 ]] && printf "\033[0;32m[INFO]\033[0m %s\n" "$*" ;;
    warn)  printf "\033[0;33m[WARN]\033[0m %s\n" "$*" >&2 ;;
    error) printf "\033[0;31m[ERROR]\033[0m %s\n" "$*" >&2 ;;
    debug) [[ $VERBOSE -eq 1 ]] && printf "\033[0;34m[DEBUG]\033[0m %s\n" "$*" ;;
  esac
}

check_requirements(){
  local missing=()
  
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    has rish || missing+=("rish (Shizuku CLI)")
  else
    has adb || missing+=("adb")
  fi
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log error "Required tools not found: ${missing[*]}"
    log error "Please install the missing tools and try again."
    exit 1
  fi
  
  # Check connection
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    rish id &>/dev/null || { log error "Shizuku connection failed. Is Shizuku running?"; exit 1; }
    log info "Using Shizuku for device access"
  else
    adb get-state &>/dev/null || { log error "ADB connection failed. Is the device connected?"; exit 1; }
    log info "Using ADB for device access"
  fi
}

# Execute a command, honouring dry-run mode
run(){
  if [[ $DRYRUN -eq 1 ]]; then
    log debug "Would run: $*"
  else
    eval "$*"
  fi
}

# --- Cache helpers ---
_cache_file_for(){ local pkg="$1"; printf '%s/%s.cache' "$CACHE_DIR" "${pkg//[^a-zA-Z0-9._+-]/_}"; }
_cache_mins(){ printf '%d' $(( (APT_FUZZ_CACHE_TTL + 59) / 60 )); }

evict_old_cache(){
  local mmin=$(( (APT_FUZZ_CACHE_TTL + 59) / 60 )) now=$(printf '%(%s)T' -1) cutoff total oldest min_mtime f ts m
  cutoff=$(( now - mmin*60 ))
  # Delete old cache files (fd/fdfind optimized, NUL-safe)
  if [[ "$FIND_TOOL" == "fd" || "$FIND_TOOL" == "fdfind" ]]; then
    while IFS= read -r -d '' f; do
      ts=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
      if (( ts < cutoff )); then
        rm -f -- "$f" || :
      fi
    done < <("$FIND_TOOL" -0 -d 1 -t f . "$CACHE_DIR" 2>/dev/null || printf '')
  else
    find "$CACHE_DIR" -maxdepth 1 -type f -mmin +"$mmin" -delete 2>/dev/null || :
  fi
}

# --- Preview generation (atomic) ---
_generate_preview(){
  local pkg="$1" out tmp
  out="$(_cache_file_for "$pkg")"
  tmp="$(mktemp "${out}.XXXXXX.tmp")" || tmp="${out}.$$.$RANDOM.tmp"
  { apt-cache show "$pkg" 2>/dev/null || :; 
    printf '\n--- changelog (first 200 lines) ---\n'
    apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :; } >"$tmp" 2>/dev/null || :
  sed -i 's/\x1b\[[0-9;]*m//g' "$tmp" 2>/dev/null || :
  mv -f "$tmp" "$out"; chmod 644 "$out" 2>/dev/null || :
}

_cached_preview_print(){
  local pkg="$1" f now f_mtime
  evict_old_cache
  f="$(_cache_file_for "$pkg")"
  now=$(printf '%(%s)T' -1)
  f_mtime=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
  if [[ -f $f ]] && (( now - f_mtime < APT_FUZZ_CACHE_TTL )); then
    cat "$f"
  else
    _generate_preview "$pkg"
    cat "$f" 2>/dev/null || echo "(no preview)"
  fi
}
export -f _cached_preview_print

# --- Manager runner (apt-get for apt) ---
run_mgr(){
  local action="$1"; shift || :
  local pkgs=("$@") cmd=()
  case "$PRIMARY_MANAGER" in
    nala)
      case "$action" in
        update) cmd=(nala update) ;;
        upgrade) cmd=(nala upgrade -y) ;;
        autoremove) cmd=(nala autoremove -y) ;;
        clean) cmd=(nala clean) ;;
        *) cmd=(nala "$action" -y "${pkgs[@]}") ;;
      esac ;;
    apt-fast)
      case "$action" in
        update) cmd=(apt-fast update) ;;
        upgrade) cmd=(apt-fast upgrade -y) ;;
        autoremove) cmd=(apt-fast autoremove -y) ;;
        clean) cmd=(apt-fast clean) ;;
        *) cmd=(apt-fast "$action" -y "${pkgs[@]}") ;;
      esac ;;
    *)
      case "$action" in
        update) cmd=(apt-get update) ;;
        upgrade) cmd=(apt-get upgrade -y) ;;
        install) cmd=(apt-get install -y "${pkgs[@]}") ;;
        remove) cmd=(apt-get remove -y "${pkgs[@]}") ;;
        purge) cmd=(apt-get purge -y "${pkgs[@]}") ;;
        autoremove) cmd=(apt-get autoremove -y) ;;
        clean) cmd=(apt-get clean) ;;
        *) cmd=(apt "$action" "${pkgs[@]}") ;;
      esac ;;
  esac
  printf 'Running: sudo %s\n' "${cmd[*]}"
  sudo "${cmd[@]}"
}

# Push file to device
push_file(){
  local src="$1" dst="$2"
  
  if [[ $DRYRUN -eq 1 ]]; then
    log debug "Would push $src to $dst"
    return 0
  }
  
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    log error "File push not supported with Shizuku yet"
    return 1
  else
    if [[ $VERBOSE -eq 1 ]]; then
      adb push "$src" "$dst"
    else
      adb push "$src" "$dst" &>/dev/null
    fi
  fi
}

# Pull file from device
pull_file(){
  local src="$1" dst="$2"
  
  if [[ $DRYRUN -eq 1 ]]; then
    log debug "Would pull $src to $dst"
    return 0
  }
  
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    log error "File pull not supported with Shizuku yet"
    return 1
  else
    if [[ $VERBOSE -eq 1 ]]; then
      adb pull "$src" "$dst"
    else
      adb pull "$src" "$dst" &>/dev/null
    fi
  fi
}

# Get free space on device
get_free_space(){
  run_cmd "df -h /data | tail -n1 | awk '{print \$4}'" | tr -d '\r'
}

# --- Manager detection ---
HAS_NALA=0; HAS_APT_FAST=0
command -v nala &>/dev/null && HAS_NALA=1 || :
command -v apt-fast &>/dev/null && HAS_APT_FAST=1 || :
PRIMARY_MANAGER="${APT_FUZZ_MANAGER:-}"
if [[ -z $PRIMARY_MANAGER ]]; then
  PRIMARY_MANAGER=apt
  [[ $HAS_NALA -eq 1 ]] && PRIMARY_MANAGER=nala
  [[ $HAS_NALA -eq 0 && $HAS_APT_FAST -eq 1 ]] && PRIMARY_MANAGER=apt-fast
fi

# Execute command via ADB or Shizuku
run_cmd(){
  if [[ $DRYRUN -eq 1 ]]; then
    log debug "Would run: $*"
    return 0
  }
  
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    if [[ $VERBOSE -eq 1 ]]; then
      rish "$@"
    else
      rish "$@" &>/dev/null
    fi
  else
    if [[ $VERBOSE -eq 1 ]]; then
      adb shell "$@"
    else
      adb shell "$@" &>/dev/null
    fi
  fi
}

# --- Clean functions ---

# Clean app caches
clean_app_caches(){
  log info "Clearing app caches..."
  
  # Clear caches for all third-party apps
  run_cmd "pm list packages -3" | cut -d: -f2 | while read -r pkg; do
    log debug "Clearing cache for: $pkg"
    run_cmd "pm clear --cache-only $pkg"
  done
  
  # Optional: Clear caches for system apps too
  if [[ "${CLEAN_SYSTEM_APPS:-0}" -eq 1 ]]; then
    run_cmd "pm list packages -s" | cut -d: -f2 | while read -r pkg; do
      log debug "Clearing cache for system app: $pkg"
      run_cmd "pm clear --cache-only $pkg"
    done
  fi
  
  # Trim caches at system level
  run_cmd "pm trim-caches 128G"
  
  log info "App caches cleared"
}

# Clean log files
clean_logs(){
  log info "Cleaning log files..."
  
  # Clear all logcat buffers
  run_cmd "logcat -b all -c"
  
  # Delete log files from storage
  run_cmd 'find /sdcard -type f \( -iname "*.log" -o -iname "*.bak" -o -iname "*.old" -o -iname "*.tmp" \) -delete'
  
  # Configure logcat buffer sizes
  run_cmd "logcat -G 128K -b main -b system"
  run_cmd "logcat -G 64K -b radio -b events -b crash"
  
  # Disable various debug logging
  run_cmd "cmd display ab-logging-disable"
  run_cmd "cmd display dwb-logging-disable"
  run_cmd "cmd looper_stats disable"
  
  log info "Log files cleaned"
}

# Clean temporary files
clean_temp_files(){
  log info "Cleaning temporary files..."
  
  # Clear /data/local/tmp (requires root or Shizuku)
  run_cmd "rm -rf /data/local/tmp/*"
  
  # Clear general temp files
  run_cmd 'find /sdcard -type f -name "*.tmp" -delete'
  
  log info "Temporary files cleaned"
}

# Clean browser cache
clean_browser_cache(){
  log info "Cleaning browser caches..."
  
  local browser_paths=(
    "/sdcard/Android/data/com.android.chrome/cache"
    "/sdcard/Android/data/org.mozilla.firefox/cache"
    "/sdcard/Android/data/com.opera.browser/cache"
    "/sdcard/Android/data/com.brave.browser/cache"
    "/sdcard/Android/data/com.samsung.android.app.sbrowser/cache"
  )
  
  for path in "${browser_paths[@]}"; do
    log debug "Checking browser cache: $path"
    run_cmd "rm -rf \"$path\"/*"
  done
  
  log info "Browser caches cleaned"
}

# Clean thumbnails
clean_thumbnails(){
  log info "Cleaning thumbnail caches..."
  
  run_cmd "rm -rf /sdcard/DCIM/.thumbnails/*"
  run_cmd "rm -rf /sdcard/Android/data/com.android.providers.media/albumthumbs/*"
  run_cmd "rm -rf /sdcard/.thumbnails/*"
  
  log info "Thumbnail caches cleaned"
}

# Clean downloads folder
clean_downloads(){
  log info "Cleaning downloads folder..."
  
  if [[ "${CLEAN_DOWNLOADS_DAYS:-0}" -gt 0 ]]; then
    run_cmd "find /sdcard/Download -type f -mtime +${CLEAN_DOWNLOADS_DAYS} -delete"
  else
    log warn "Skipping downloads cleanup as CLEAN_DOWNLOADS_DAYS is not set"
  fi
  
  log info "Downloads folder cleaned"
}

# --- WhatsApp media functions ---

# Clean old opus files
clean_whatsapp_opus(){
  local delete_days="${DELETE_OPUS_DAYS:-90}"
  log info "Cleaning opus files older than $delete_days days"
  
  for path in "${WHATSAPP_OPUS_PATHS[@]}"; do
    log info "Processing: $path"
    
    if [[ $DRYRUN -eq 1 ]]; then
      # Just list files that would be deleted
      run_cmd find \""$path"\" -type f -name \"*.opus\" -mtime +"$delete_days" -exec ls -la {} \\\;
      
      # Count files that would be deleted
      local count
      count=$(run_cmd find \""$path"\" -type f -name \"*.opus\" -mtime +"$delete_days" | wc -l)
      log info "Would delete $count opus files from $path"
    else
      # Actually delete the files
      run_cmd find \""$path"\" -type f -name \"*.opus\" -mtime +"$delete_days" -delete
      log info "Deleted opus files older than $delete_days days from $path"
    fi
  done
}

# Clean specific WhatsApp paths completely
clean_whatsapp_paths(){
  log info "Cleaning specific WhatsApp folders"
  
  for path in "${WHATSAPP_CLEAN_PATHS[@]}"; do
    log info "Processing: $path"
    
    if [[ $DRYRUN -eq 1 ]]; then
      # Count files that would be deleted
      local count
      count=$(run_cmd find \""$path"\" -type f | wc -l)
      log info "Would delete $count files from $path"
    else
      # Delete all files in the path
      run_cmd rm -rf \""$path"/\"*
      log info "Deleted all files in $path"
    fi
  done
}

# Optimize WhatsApp images
optimize_whatsapp_images(){
  [[ "${OPTIMIZE_IMAGES:-1}" -ne 1 ]] && return
  
  log info "Optimizing images"
  
  # Check if we have optimization tools
  local has_tools=0
  
  run_cmd "command -v fclones" &>/dev/null && has_tools=1
  run_cmd "command -v rimage" &>/dev/null && has_tools=1
  run_cmd "command -v flaca" &>/dev/null && has_tools=1
  run_cmd "command -v compresscli" &>/dev/null && has_tools=1
  run_cmd "command -v imgc" &>/dev/null && has_tools=1
  
  if [[ $has_tools -eq 0 ]]; then
    log warn "No image optimization tools found. Install tools like fclones, rimage, flaca, compresscli, or imgc in Termux."
    return
  fi

  for path in "${WHATSAPP_IMAGE_PATHS[@]}"; do
    log info "Processing images in: $path"
    
    # First try to deduplicate with fclones if available
    if run_cmd "command -v fclones" &>/dev/null; then
      log info "Deduplicating images with fclones"
      
      if [[ $DRYRUN -eq 1 ]]; then
        log info "Would deduplicate images in $path"
      else
        # Find groups of duplicate images
        run_cmd "fclones group -r \"$path\" --threads $JOBS"
        
        # Remove duplicates keeping the oldest
        run_cmd "fclones dedupe --strategy=oldestrandom \"$path\""
      fi
    fi
    
    # Try to optimize with available tools in order of preference
    if [[ $DRYRUN -eq 1 ]]; then
      log info "Would optimize images in $path with available tools"
    else
      if run_cmd "command -v rimage" &>/dev/null; then
        log info "Optimizing with rimage"
        run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) -exec rimage -i {} -o {} \\;"
      elif run_cmd "command -v flaca" &>/dev/null; then
        log info "Optimizing with flaca"
        run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) -exec flaca {} \\;"
      elif run_cmd "command -v compresscli" &>/dev/null; then
        log info "Optimizing with compresscli"
        run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) -exec compresscli {} \\;"
      elif run_cmd "command -v imgc" &>/dev/null; then
        log info "Optimizing with imgc"
        run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) -exec imgc {} \\;"
      else
        log warn "No image optimization tools found for $path"
      fi
    fi
  done
}

# --- Device optimization functions ---

# Optimize Android Runtime
optimize_art_runtime(){
  log info "Optimizing ART runtime..."
  
  # Run any postponed dex-opt jobs immediately
  run_cmd "pm bg-dexopt-job --enable"
  run_cmd "cmd jobscheduler run -f android \$(cmd jobscheduler list-jobs android | grep background-dexopt | awk '{print \$2}')"
  
  # Optimize packages with different strategies
  run_cmd "cmd package compile -af --full --secondary-dex -m speed-profile"
  run_cmd "cmd package compile -a -f --full --secondary-dex -m speed"
  run_cmd "pm art dexopt-packages -r bg-dexopt"
  
  log info "ART runtime optimized"
}

# Configure rendering settings
configure_rendering(){
  log info "Configuring rendering settings..."
  
  # GPU Rendering
  run_cmd "settings put global force_gpu_rendering 1"
  run_cmd "settings put global debug.hwui.force_gpu_command_drawing 1"
  run_cmd "settings put global debug.hwui.use_disable_overdraw 1"
  run_cmd "settings put global skia.force_gl_texture 1"
  
  # Hardware acceleration
  run_cmd "settings put global enable_hardware_acceleration 1"
  run_cmd "settings put global hardware_accelerated_rendering_enabled 1"
  run_cmd "settings put global hardware_accelerated_graphics_decoding 1"
  run_cmd "settings put global hardware_accelerated_video_decode 1"
  run_cmd "settings put global hardware_accelerated_video_encode 1"
  
  # SF properties
  run_cmd "setprop debug.sf.disable_backpressure 0"
  run_cmd "setprop debug.sf.predict_hwc_composition_strategy 1"
  run_cmd "setprop debug.sf.use_phase_offsets_as_durations 1"
  run_cmd "setprop debug.sf.enable_gl_backpressure 1"
  
  log info "Rendering settings configured"
}

# Configure audio settings
configure_audio(){
  log info "Configuring audio settings..."
  
  # Audio optimization
  run_cmd "settings put global audio.deep_buffer.media true"
  run_cmd "settings put global audio.offload.video true"
  run_cmd "settings put global audio.offload.track.enable true"
  
  # Media optimization
  run_cmd "settings put global media.stagefright.thumbnail.prefer_hw_codecs true"
  
  log info "Audio settings configured"
}

# Configure battery optimization
configure_battery(){
  log info "Configuring battery optimizations..."
  
  # Battery saver settings
  run_cmd "settings put global battery_saver_constants \"vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,fullbackup_deferred=true,keyvaluebackup_deferred=true,gps_mode=low_power,data_saver=true,optional_sensors_disabled=true,advertiser_id_enabled=false\""
  run_cmd "settings put global dynamic_power_savings_enabled 1"
  run_cmd "settings put global adaptive_battery_management_enabled 0"
  run_cmd "settings put global app_auto_restriction_enabled 1"
  run_cmd "settings put global cached_apps_freezer enabled"
  
  log info "Battery optimizations configured"
}

# Configure network settings
configure_network(){
  log info "Configuring network settings..."
  
  # Data saver
  run_cmd "settings put global data_saver_mode 1"
  run_cmd "cmd netpolicy set restrict-background true"
  
  # WiFi optimization
  run_cmd "settings put global wifi_suspend_optimizations_enabled 2"
  run_cmd "settings put global wifi_stability 1"
  run_cmd "settings put global network_avoid_bad_wifi 1"
  
  # DNS
  if [[ -n "${CUSTOM_DNS:-}" ]]; then
    run_cmd "settings put global private_dns_mode hostname"
    run_cmd "settings put global private_dns_specifier $CUSTOM_DNS"
  fi
  
  log info "Network settings configured"
}

# Configure input settings
configure_input(){
  log info "Configuring input settings..."
  
  # Touch optimization
  run_cmd "settings put global touch_calibration 1"
  run_cmd "settings put global touch.size.scale 1"
  run_cmd "settings put secure touch_blocking_period 0.0"
  run_cmd "settings put secure tap_duration_threshold 0.0"
  run_cmd "settings put secure long_press_timeout 250"
  run_cmd "settings put secure multi_press_timeout 250"
  
  # Animation settings
  run_cmd "settings put global animator_duration_scale 0.0"
  run_cmd "settings put global transition_animation_scale 0.0"
  run_cmd "settings put global window_animation_scale 0.0"
  run_cmd "settings put system remove_animations 1"
  run_cmd "settings put system reduce_animations 1"
  
  log info "Input settings configured"
}

# Configure system settings
configure_system(){
  log info "Configuring system settings..."
  
  # System UI
  run_cmd "settings put global window_focus_timeout 250"
  run_cmd "device_config put systemui window_cornerRadius 0"
  run_cmd "device_config put systemui window_blur 0"
  run_cmd "device_config put systemui window_shadow 0"
  
  # Graphics
  run_cmd "device_config put graphics render_thread_priority high"
  run_cmd "device_config put graphics enable_gpu_boost true"
  run_cmd "device_config put graphics enable_cpu_boost true"
  
  log info "System settings configured"
}

# Configure doze and app standby
configure_doze(){
  log info "Configuring doze and app standby..."
  
  # Force doze
  run_cmd "cmd deviceidle force-idle"
  run_cmd "cmd deviceidle unforce"
  
  # Whitelist important apps
  run_cmd "dumpsys deviceidle whitelist +com.android.systemui"
  
  # App ops
  run_cmd "cmd appops set com.google.android.gms START_FOREGROUND ignore"
  run_cmd "cmd appops set com.google.android.gms INSTANT_APP_START_FOREGROUND ignore"
  
  log info "Doze and app standby configured"
}

# --- App permissions management ---

# Set app permission
set_app_permission(){
  local mode="$1" pkg="$2"
  
  case "$mode" in
    dump)
      run_cmd "pm grant \"$pkg\" android.permission.DUMP"
      log info "Granted DUMP permission to $pkg"
      ;;
    write)
      run_cmd "pm grant \"$pkg\" android.permission.WRITE_SECURE_SETTINGS"
      log info "Granted WRITE_SECURE_SETTINGS permission to $pkg"
      ;;
    doze)
      run_cmd "dumpsys deviceidle whitelist +\"$pkg\""
      log info "Whitelisted $pkg for doze"
      ;;
    *)
      log error "Unknown permission mode: $mode"
      return 1
      ;;
  esac
}

# Load app permissions from config file
load_app_permissions(){
  [[ ! -f "$CONFIG_FILE" ]] && return 1
  
  log info "Loading app permissions from config file"
  
  # Very simple TOML parser for the permissions section
  local in_perm_section=0
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Detect section headers [section]
    if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
      [[ "${BASH_REMATCH[1]}" == "permission" ]] && in_perm_section=1 || in_perm_section=0
      continue
    fi
    
    # Only process lines in the permission section
    [[ $in_perm_section -eq 0 ]] && continue
    
    # Parse key=value
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      local pkg="${BASH_REMATCH[1]}"
      local perms="${BASH_REMATCH[2]}"
      
      # Split comma-separated permissions and apply
      IFS=',' read -ra perm_array <<< "$perms"
      for perm in "${perm_array[@]}"; do
        set_app_permission "$perm" "$pkg"
      done
    fi
  done < "$CONFIG_FILE"
  
  log info "App permissions applied"
  return 0
}

# --- Usage/help functions ---

# Show detailed usage for the script
usage(){
  cat <<EOF
Android Toolkit - Comprehensive Android device management utility

Usage: $(basename "$0") [OPTIONS] COMMAND [COMMAND_OPTIONS]

Global Options:
  -d, --dry-run       Show what would be done without making changes
  -v, --verbose       Enable verbose output
  -s, --shizuku       Use Shizuku (rish) instead of ADB
  -j, --jobs JOBS     Number of parallel jobs for optimization (default: auto)
  -h, --help          Show this help message

Commands:
  clean               Clean device caches and temporary files
    --system-apps       Also clean system app caches (not just user apps)
    --downloads DAYS    Clean files in Downloads older than DAYS
    --no-browser        Skip browser cache cleaning
    --no-thumbnails     Skip thumbnail cache cleaning

  whatsapp-clean      Clean WhatsApp media files
    --days DAYS         Delete opus files older than DAYS (default: 90)
    --no-images         Skip image optimization

  optimize            Apply device optimizations
    [CATEGORIES...]     Specify categories to optimize (default: all)
                        Categories: art, rendering, audio, battery, network,
                        input, system, doze, all
    --dns SERVER        Set custom DNS server for private DNS

  permissions         Apply app permissions
    list                List permissions in config file
    add PACKAGE PERM    Add permission to config file
    apply               Apply permissions from config file (default)
    grant PACKAGE PERM  Grant permission to package directly

  maintenance         System maintenance tasks
    update              Update package lists
    upgrade             Upgrade installed packages
    autoremove          Remove unused dependencies
    clean               Clean package cache

  backup-restore      Backup or restore installed package lists
    backup              Backup currently installed packages
    restore FILE        Restore packages from a file

Examples:
  $(basename "$0") clean              # Clean device caches and temporary files
  $(basename "$0") whatsapp-clean --days 30 --no-images  # Clean old WhatsApp media
  $(basename "$0") optimize rendering audio  # Apply specific optimizations
  $(basename "$0") -s optimize        # Use Shizuku for device access
  $(basename "$0") permissions grant com.example.app write,doze

For more detailed help on a specific command, use: $(basename "$0") COMMAND --help
EOF
}

# Show command-specific help
command_help(){
  local cmd="$1"
  
  case "$cmd" in
    clean)
      cat <<EOF
Android Toolkit - Clean Command

Usage: $(basename "$0") clean [OPTIONS]

Clean Android device caches, logs, and temporary files

Options:
  --system-apps       Also clean system app caches (not just user apps)
  --downloads DAYS    Clean files in Downloads older than DAYS
  --no-browser        Skip browser cache cleaning
  --no-thumbnails     Skip thumbnail cache cleaning
  
  -d, --dry-run       Show what would be done without making changes
  -v, --verbose       Enable verbose output
  -s, --shizuku       Use Shizuku (rish) instead of ADB

Examples:
  $(basename "$0") clean --system-apps --downloads 30
  $(basename "$0") clean -d -s
EOF
      ;;
    whatsapp-clean)
      cat <<EOF
Android Toolkit - WhatsApp Clean Command

Usage: $(basename "$0") whatsapp-clean [OPTIONS]

Clean WhatsApp media files (voice notes, images, stickers)

Options:
  --days DAYS         Delete opus files older than DAYS (default: 90)
  --no-images         Skip image optimization
  
  -d, --dry-run       Show what would be done without making changes
  -v, --verbose       Enable verbose output
  -s, --shizuku       Use Shizuku (rish) instead of ADB
  -j, --jobs JOBS     Number of parallel jobs for optimization (default: auto)

Examples:
  $(basename "$0") whatsapp-clean --days 60
  $(basename "$0") whatsapp-clean --no-images
EOF
      ;;
    optimize)
      cat <<EOF
Android Toolkit - Optimize Command

Usage: $(basename "$0") optimize [OPTIONS] [CATEGORIES...]

Apply device optimizations for better performance

Categories:
  art                 Optimize Android Runtime
  rendering           Configure rendering settings
  audio               Configure audio settings
  battery             Configure battery optimization
  network             Configure network settings
  input               Configure input settings
  system              Configure system settings
  doze                Configure doze and app standby
  all                 Apply all optimizations (default)
  
Options:
  -d, --dry-run       Show what would be done without making changes
  -v, --verbose       Enable verbose output
  -s, --shizuku       Use Shizuku (rish) instead of ADB
  --dns SERVER        Set custom DNS server for private DNS

Examples:
  $(basename "$0") optimize art battery network
  $(basename "$0") optimize all --dns dns.google
EOF
      ;;
    permissions)
      cat <<EOF
Android Toolkit - Permissions Command

Usage: $(basename "$0") permissions [OPTIONS] [ACTION] [PACKAGE] [PERMISSION]

Manage app permissions on device

Actions:
  list                List permissions in config file
  add                 Add permission to config file
  apply               Apply permissions from config file (default)
  grant               Grant permission to package directly
  
Options:
  -d, --dry-run       Show what would be done without making changes
  -v, --verbose       Enable verbose output
  -s, --shizuku       Use Shizuku (rish) instead of ADB

Permission types:
  dump                Grant android.permission.DUMP
  write               Grant android.permission.WRITE_SECURE_SETTINGS
  doze                Whitelist for doze mode

Examples:
  $(basename "$0") permissions apply
  $(basename "$0") permissions add com.example.app write,doze
  $(basename "$0") permissions grant com.example.app dump
EOF
      ;;
    maintenance)
      cat <<EOF
Android Toolkit - Maintenance Command

Usage: $(basename "$0") maintenance [ACTION]

Perform system maintenance tasks

Actions:
  update              Update package lists
  upgrade             Upgrade installed packages
  autoremove          Remove unused dependencies
  clean               Clean package cache
  
Options:
  -d, --dry-run       Show what would be done without making changes
  -v, --verbose       Enable verbose output

Examples:
  $(basename "$0") maintenance update
  $(basename "$0") maintenance upgrade
EOF
      ;;
    backup-restore)
      cat <<EOF
Android Toolkit - Backup/Restore Command

Usage: $(basename "$0") backup-restore [ACTION] [FILE]

Backup or restore installed package lists

Actions:
  backup              Backup currently installed packages (default: pkglist-DATE.txt)
  restore FILE        Restore packages from a file
  
Options:
  -d, --dry-run       Show what would be done without making changes
  -v, --verbose       Enable verbose output

Examples:
  $(basename "$0") backup-restore backup
  $(basename "$0") backup-restore restore pkglist-20251008.txt
EOF
      ;;
    *)
      usage
      ;;
  esac
}

choose_manager(){
  local opts=(apt) choice
  [[ $HAS_NALA -eq 1 ]] && opts+=("nala")
  [[ $HAS_APT_FAST -eq 1 ]] && opts+=("apt-fast")
  choice=$(printf '%s\n' "${opts[@]}" | "$FINDER" "${FINDER_OPTS[@]}" --height=12% --prompt="Manager> ")
  [[ -n $choice ]] && PRIMARY_MANAGER="$choice"
}

# --- Command handlers ---

# Clean command handler
cmd_clean(){
  local clean_system=0 clean_downloads=0 skip_browser=0 skip_thumbnails=0
  
  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --system-apps)
        clean_system=1
        shift
        ;;
      --downloads)
        clean_downloads="$2"
        shift 2
        ;;
      --no-browser)
        skip_browser=1
        shift
        ;;
      --no-thumbnails)
        skip_thumbnails=1
        shift
        ;;
      --help|-h)
        command_help clean
        return 0
        ;;
      *)
        log error "Unknown option: $1"
        command_help clean
        return 1
        ;;
    esac
  done
  
  # Perform cleaning operations
  check_requirements
  
  # Export options for subfunctions
  export CLEAN_SYSTEM_APPS=$clean_system
  export CLEAN_DOWNLOADS_DAYS=$clean_downloads
  
  # Get initial free space
  local free_space_before
  free_space_before=$(get_free_space)
  
  log info "Starting cleanup process. Initial free space: $free_space_before"
  
  # Run cleaning operations
  clean_app_caches
  clean_logs
  clean_temp_files
  
  [[ $skip_browser -eq 0 ]] && clean_browser_cache
  [[ $skip_thumbnails -eq 0 ]] && clean_thumbnails
  
  [[ $clean_downloads -gt 0 ]] && clean_downloads
  
  # Get final free space
  local free_space_after
  free_space_after=$(get_free_space)
  
  log info "Cleanup completed. Free space now: $free_space_after"
}

# WhatsApp clean command handler
cmd_whatsapp_clean(){
  local delete_days=90 optimize_images=1
  
  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)
        delete_days="$2"
        shift 2
        ;;
      --no-images)
        optimize_images=0
        shift
        ;;
      --help|-h)
        command_help whatsapp-clean
        return 0
        ;;
      *)
        log error "Unknown option: $1"
        command_help whatsapp-clean
        return 1
        ;;
    esac
  done
  
  # Perform WhatsApp cleaning operations
  check_requirements
  
  # Export options for subfunctions
  export DELETE_OPUS_DAYS=$delete_days
  export OPTIMIZE_IMAGES=$optimize_images
  
  # Get initial free space
  local free_space_before
  free_space_before=$(get_free_space)
  
  log info "Starting WhatsApp cleanup process. Initial free space: $free_space_before"
  
  # Run cleaning operations
  clean_whatsapp_opus
  clean_whatsapp_paths
  [[ $optimize_images -eq 1 ]] && optimize_whatsapp_images
  
  # Get final free space
  local free_space_after
  free_space_after=$(get_free_space)
  
  log info "WhatsApp cleanup completed. Free space now: $free_space_after"
}

# Optimize command handler
cmd_optimize(){
  local categories=() custom_dns=""
  
  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dns)
        custom_dns="$2"
        shift 2
        ;;
      --help|-h)
        command_help optimize
        return 0
        ;;
      art|rendering|audio|battery|network|input|system|doze|all)
        categories+=("$1")
        shift
        ;;
      *)
        log error "Unknown option or category: $1"
        command_help optimize
        return 1
        ;;
    esac
  done
  
  # Default to all if no categories specified
  [[ ${#categories[@]} -eq 0 ]] && categories=("all")
  
  # Perform optimization operations
  check_requirements
  
  # Export options for subfunctions
  [[ -n $custom_dns ]] && export CUSTOM_DNS=$custom_dns
  
  log info "Starting device optimization for categories: ${categories[*]}"
  
  # Run optimization operations
  for category in "${categories[@]}"; do
    case "$category" in
      art)
        optimize_art_runtime
        ;;
      rendering)
        configure_rendering
        ;;
      audio)
        configure_audio
        ;;
      battery)
        configure_battery
        ;;
      network)
        configure_network
        ;;
      input)
        configure_input
        ;;
      system)
        configure_system
        ;;
      doze)
        configure_doze
        ;;
      all)
        optimize_art_runtime
        configure_rendering
        configure_audio
        configure_battery
        configure_network
        configure_input
        configure_system
        configure_doze
        ;;
    esac
  done
  
  log info "Device optimization completed"
}

# Permissions command handler
cmd_permissions(){
  local action="apply" pkg="" perm=""
  
  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      list|add|apply|grant)
        action="$1"
        shift
        ;;
      --help|-h)
        command_help permissions
        return 0
        ;;
      *)
        if [[ -z $pkg ]]; then
          pkg="$1"
          shift
        elif [[ -z $perm ]]; then
          perm="$1"
          shift
        else
          log error "Too many arguments: $1"
          command_help permissions
          return 1
        fi
        ;;
    esac
  done
  
  # Ensure config directory exists
  mkdir -p "$CONFIG_DIR" &>/dev/null
  
  # Handle permission actions
  case "$action" in
    list)
      [[ ! -f "$CONFIG_FILE" ]] && { log error "Config file not found: $CONFIG_FILE"; return 1; }
      log info "Permissions in config file:"
      grep -A 100 "^\[permission\]" "$CONFIG_FILE" | grep -v "^\["
      ;;
    add)
      [[ -z $pkg || -z $perm ]] && { log error "Missing package or permission"; command_help permissions; return 1; }
      
      # Create config file if it doesn't exist
      if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
# Android Toolkit Configuration
# Format:
# [permission]
# app.package.name=dump,write,doze
# another.package=dump

[permission]
EOF
      fi
      
      # Check if permission section exists
      if ! grep -q "^\[permission\]" "$CONFIG_FILE"; then
        echo -e "\n[permission]" >> "$CONFIG_FILE"
      fi
      
      # Check if package already has permissions
      if grep -q "^$pkg=" "$CONFIG_FILE"; then
        # Update existing entry
        sed -i "s/^$pkg=.*/$pkg=$perm/" "$CONFIG_FILE"
      else
        # Add new entry
        echo "$pkg=$perm" >> "$CONFIG_FILE"
      fi
      
      log info "Added permission $perm for $pkg to config file"
      ;;
    apply)
      check_requirements
      load_app_permissions
      ;;
    grant)
      [[ -z $pkg || -z $perm ]] && { log error "Missing package or permission"; command_help permissions; return 1; }
      check_requirements
      
      # Handle comma-separated permissions
      IFS=',' read -ra perm_array <<< "$perm"
      for p in "${perm_array[@]}"; do
        set_app_permission "$p" "$pkg"
      done
      ;;
  esac
}

# Maintenance command handler
cmd_maintenance(){
  local action=""
  
  # Parse options
  if [[ $# -gt 0 ]]; then
    action="$1"
    shift
  else
    action="update"  # Default action
  fi
  
  case "$action" in
    update)
      run_mgr update
      ;;
    upgrade)
      run_mgr upgrade
      ;;
    autoremove)
      run_mgr autoremove
      ;;
    clean)
      run_mgr clean
      ;;
    --help|-h)
      command_help maintenance
      return 0
      ;;
    *)
      log error "Unknown maintenance action: $action"
      command_help maintenance
      return 1
      ;;
  esac
}

# Backup/restore command handler
cmd_backup_restore(){
  local action="" file=""
  
  # Parse options
  if [[ $# -gt 0 ]]; then
    action="$1"
    shift
  else
    action="backup"  # Default action
  fi
  
  if [[ $# -gt 0 ]]; then
    file="$1"
    shift
  fi
  
  case "$action" in
    backup)
      local out="${file:-pkglist-$(date +%Y%m%d).txt}"
      adb shell pm list packages | cut -d: -f2 > "$out"
      log info "Saved package list to $out"
      ;;
    restore)
      [[ -z $file ]] && { log error "No file specified for restore"; command_help backup-restore; return 1; }
      [[ ! -f $file ]] && { log error "File not found: $file"; return 1; }
      
      log info "Installing packages from $file..."
      while IFS= read -r pkg; do
        [[ -z $pkg ]] && continue
        run_cmd "pm install \"$pkg\"" || log warn "Failed to install $pkg"
      done < "$file"
      ;;
    --help|-h)
      command_help backup-restore
      return 0
      ;;
    *)
      log error "Unknown backup-restore action: $action"
      command_help backup-restore
      return 1
      ;;
  esac
}

# Initialize config/cache directories
init_dirs(){
  mkdir -p "$CONFIG_DIR" "$CACHE_DIR" &>/dev/null
  
  # Create default config if it doesn't exist
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<EOF
# Android Toolkit Configuration
# Format:
# [permission]
# app.package.name=dump,write,doze
# another.package=dump
#
# [compilation]
# app.package.name=PRIORITY_INTERACTIVE_FAST:speed-profile
# another.app=PRIORITY_DEFAULT:verify

[permission]
com.pittvandewitt.wavelet=dump,write
com.termux=write,dump,doze
moe.shizuku.privileged.api=write

[compilation]
com.android.chrome=PRIORITY_INTERACTIVE_FAST:speed-profile
com.android.systemui=PRIORITY_FOREGROUND:speed
com.google.android.gms=PRIORITY_BACKGROUND:verify
EOF
  fi
}

# --- Main Program ---

main(){
  # Initialize directories
  init_dirs
  
  # Parse global options
  while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
      -d|--dry-run)
        DRYRUN=1
        shift
        ;;
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      -s|--shizuku)
        USE_SHIZUKU=1
        shift
        ;;
      -j|--jobs)
        JOBS="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        # End of global options
        break
        ;;
    esac
  done
  
  # No command specified - show usage
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi
  
  # Execute command
  local cmd="$1"
  shift
  
  case "$cmd" in
    clean)
      cmd_clean "$@"
      ;;
    whatsapp-clean)
      cmd_whatsapp_clean "$@"
      ;;
    optimize)
      cmd_optimize "$@"
      ;;
    permissions)
      cmd_permissions "$@"
      ;;
    maintenance)
      cmd_maintenance "$@"
      ;;
    backup-restore)
      cmd_backup_restore "$@"
      ;;
    help)
      [[ $# -eq 0 ]] && usage || command_help "$1"
      ;;
    *)
      log error "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

# Run main with all arguments
main "$@"
