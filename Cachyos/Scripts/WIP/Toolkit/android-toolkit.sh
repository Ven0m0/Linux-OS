#!/usr/bin/env bash
# android-toolkit.sh - Android device optimization and media management toolkit
#
# Features:
# - Device optimization: battery, memory, network, graphics
# - Image and APK optimization with flaca/rimage/oxipng
# - System cleanup and maintenance
# - Package management through ADB and Shizuku
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"

# ----------------------------------------------------------------------
# Configuration and Environment
# ----------------------------------------------------------------------
DRY_RUN=0                 # Set to 1 to only print actions, don't modify
DEBUG=0                   # Set to 1 to enable verbose output
LOSSY=0                   # Set to 1 for lossy image compression
BACKUP_DIR="${HOME}/android_backup_$(date +%Y%m%d)"
LOG_FILE="/tmp/android-toolkit-$(date +%s).log"
TEMP_DIR=$(mktemp -d)

# ----------------------------------------------------------------------
# Helper functions
# ----------------------------------------------------------------------
log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG_FILE"
}

log_debug() {
  (( DEBUG )) && printf '[DEBUG %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG_FILE"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "❌ Required command \"$1\" not found."
    case "$1" in
      adb) log "Install Android SDK Platform Tools" ;;
      aapt*) log "Install Android SDK Build Tools" ;;
      oxipng) log "Install oxipng (preferred) or optipng" ;;
      rimage) log "Install rimage: cargo install rimage" ;;
      flaca) log "Install flaca: cargo install flaca" ;;
    esac
    return 1
  }
  return 0
}

run() {
  # Execute a command, honoring dry‑run mode
  if (( DRY_RUN )); then
    log "[dry‑run] $*"
  else
    eval "$*"
  fi
}

# ----------------------------------------------------------------------
# ADB Connection Management
# ----------------------------------------------------------------------
check_adb_connection() {
  local device_count
  
  # Start ADB server if not running
  run adb start-server
  
  # Get connected devices
  if [[ -z "${ADB_DEVICE:-}" ]]; then
    device_count=$(adb devices | grep -c -v "List of devices\|^$")
    
    if [[ $device_count -eq 0 ]]; then
      log "No Android devices found. Connect a device and try again."
      return 1
    elif [[ $device_count -gt 1 ]]; then
      log "Multiple devices found. Using first connected device."
      ADB_DEVICE=$(adb devices | grep -v "List of devices\|^$" | head -1 | awk '{print $1}')
      log "Selected device: $ADB_DEVICE"
    else
      ADB_DEVICE=$(adb devices | grep -v "List of devices\|^$" | awk '{print $1}')
    fi
  else
    if ! adb devices | grep -q "$ADB_DEVICE"; then
      log "Specified device '$ADB_DEVICE' not found."
      return 1
    fi
  fi
  
  # Check if device is responsive
  if ! adb -s "$ADB_DEVICE" shell echo "Connection test" >/dev/null; then
    log "Device is not responding."
    return 1
  fi
  
  log "Connected to device: $ADB_DEVICE"
  return 0
}

# ----------------------------------------------------------------------
# Image Optimization
# ----------------------------------------------------------------------
optimize_image() {
  local input="$1" output="${2:-${1}}"
  local ext="${input##*.}"
  ext="${ext,,}"  # Convert to lowercase
  local tmpfile="$(mktemp "${TEMP_DIR}/${ext}.XXXXXX")"
  local orig_size new_size
  
  cp -a "$input" "$tmpfile" || return 1
  orig_size=$(stat -c "%s" "$input" 2>/dev/null || stat -f "%z" "$input" 2>/dev/null || echo 0)
  
  log_debug "Optimizing ${input} (${ext})"
  
  # Use different tools based on file type
  case "$ext" in
    png)
      # Try flaca if available (performs oxipng optimizations internally)
      if require_cmd flaca; then
        flaca --no-symlinks "$tmpfile" &>/dev/null || true
      # Or use oxipng directly
      elif require_cmd oxipng; then
        oxipng -o 4 -s -a --strip safe -i 0 "$tmpfile" &>/dev/null || true
      # Try rimage as a fallback
      elif require_cmd rimage; then
        rimage -i "$tmpfile" -o "$tmpfile.new" &>/dev/null && mv "$tmpfile.new" "$tmpfile" || true
      # Last resort: optipng or pngquant
      else
        if require_cmd optipng; then
          optipng -quiet -strip all -o5 "$tmpfile" &>/dev/null || true
        fi
        if (( LOSSY )) && require_cmd pngquant; then
          pngquant --force --skip-if-larger --quality=65-85 --speed=1 --strip --output "$tmpfile.tmp" -- "$tmpfile" &>/dev/null && 
            mv "$tmpfile.tmp" "$tmpfile" || true
        fi
      fi
      ;;
      
    jpg|jpeg)
      # Try flaca first for JPEGs
      if require_cmd flaca; then
        flaca --no-symlinks "$tmpfile" &>/dev/null || true
      # Try rimage next
      elif require_cmd rimage; then
        rimage -i "$tmpfile" -o "$tmpfile.new" &>/dev/null && mv "$tmpfile.new" "$tmpfile" || true
      # Fall back to jpegoptim
      elif require_cmd jpegoptim; then
        if (( LOSSY )); then
          jpegoptim --strip-all --all-progressive --max=85 -o -- "$tmpfile" &>/dev/null || true
        else
          jpegoptim --strip-all --all-progressive --force -- "$tmpfile" &>/dev/null || true
        fi
      fi
      ;;
      
    gif)
      if require_cmd gifsicle; then
        if (( LOSSY )); then
          local colors=256
          [[ "$LOSSY" -gt 1 ]] && colors=128
          gifsicle -O3 --colors "$colors" --no-warnings --batch -- "$tmpfile" &>/dev/null || true
        else
          gifsicle -O3 --no-warnings --batch -- "$tmpfile" &>/dev/null || true
        fi
      fi
      ;;
      
    svg)
      if require_cmd svgo; then
        svgo --multipass -q "$tmpfile" &>/dev/null || true
      fi
      ;;
      
    webp)
      if require_cmd cwebp && require_cmd dwebp; then
        if (( LOSSY )); then
          local tmp_png="${tmpfile}.png"
          dwebp "$tmpfile" -o "$tmp_png" &>/dev/null && \
          cwebp -q 80 "$tmp_png" -o "$tmpfile" &>/dev/null && \
          rm -f "$tmp_png" || true
        fi
      elif require_cmd rimage; then
        rimage -i "$tmpfile" -o "$tmpfile.new" &>/dev/null && mv "$tmpfile.new" "$tmpfile" || true
      fi
      ;;
  esac
  
  new_size=$(stat -c "%s" "$tmpfile" 2>/dev/null || stat -f "%z" "$tmpfile" 2>/dev/null || echo 0)
  
  # Only replace original if the optimized version is smaller
  if [[ $new_size -gt 0 && $new_size -lt $orig_size ]]; then
    if [[ "$input" != "$output" ]]; then
      # If output path is different, move the optimized file there
      mv "$tmpfile" "$output"
    else
      # Otherwise replace the input file
      mv "$tmpfile" "$input"
    fi
    log "Optimized: ${input} ($(( (orig_size - new_size) / 1024 )) KB saved)"
    return 0
  else
    rm -f "$tmpfile"
    log_debug "No improvement for ${input}, kept original"
    return 1
  fi
}

# ----------------------------------------------------------------------
# APK Optimization
# ----------------------------------------------------------------------
optimize_apk() {
  local input_apk="$1"
  local output_apk="${2:-${input_apk%.apk}-optimized.apk}"
  local tmpdir="${TEMP_DIR}/apk_opt"
  local decoded_dir="${tmpdir}/decoded"
  local build_dir="${tmpdir}/build"
  
  log "Optimizing APK: $input_apk -> $output_apk"
  
  # Check if the input APK exists
  if [[ ! -f "$input_apk" ]]; then
    log "Input APK not found: $input_apk"
    return 1
  fi
  
  # Required tools
  require_cmd zipalign || return 1
  require_cmd apksigner || return 1
  
  mkdir -p "$decoded_dir" "$build_dir"
  
  # Extract APK
  run unzip -q "$input_apk" -d "$decoded_dir"
  
  # Optimize images in the APK
  find "$decoded_dir" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.webp" \) -print0 |
    xargs -0 -P "$(nproc 2>/dev/null || echo 2)" -I{} bash -c "
      source \"$0\"
      optimize_image \"\$1\"
    " _ {} || true
  
  # Repack APK
  log "Repacking APK..."
  (cd "$decoded_dir" && run zip -q -r "$build_dir/unaligned.apk" .)
  
  # Zipalign
  log "Aligning APK..."
  run zipalign -v -f -p 4 "$build_dir/unaligned.apk" "$build_dir/aligned.apk"
  
  # Sign APK
  log "Signing APK..."
  if [[ -n "${KEYSTORE_PATH:-}" && -n "${KEY_ALIAS:-}" ]]; then
    run apksigner sign --ks "$KEYSTORE_PATH" \
      --ks-key-alias "$KEY_ALIAS" \
      --ks-pass "pass:${KEYSTORE_PASS:-}" \
      --key-pass "pass:${KEY_PASS:-}" \
      --out "$output_apk" "$build_dir/aligned.apk"
  else
    log "No keystore configured, creating debug-signed APK"
    local debug_keystore="${HOME}/.android/debug.keystore"
    if [[ ! -f "$debug_keystore" ]]; then
      mkdir -p "${HOME}/.android"
      run keytool -genkey -v -keystore "$debug_keystore" \
        -storepass android -alias androiddebugkey \
        -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
    fi
    run apksigner sign --ks "$debug_keystore" \
      --ks-key-alias androiddebugkey \
      --ks-pass pass:android \
      --key-pass pass:android \
      --out "$output_apk" "$build_dir/aligned.apk"
  fi
  
  # Verify
  if (( !DRY_RUN )); then
    local orig_size=$(stat -c "%s" "$input_apk" 2>/dev/null || stat -f "%z" "$input_apk" 2>/dev/null || echo 0)
    local new_size=$(stat -c "%s" "$output_apk" 2>/dev/null || stat -f "%z" "$output_apk" 2>/dev/null || echo 0)
    if [[ $new_size -gt 0 && $new_size -lt $orig_size ]]; then
      log "APK optimized: ${input_apk} ($(( (orig_size - new_size) / 1024 )) KB saved)"
    else
      log "APK size not improved: ${input_apk}"
    fi
  fi
  
  return 0
}

# ----------------------------------------------------------------------
# Device Optimization Functions
# ----------------------------------------------------------------------
optimize_device() {
  log "Running device optimization..."
  check_adb_connection || return 1
  
  # Create backup of current settings
  if [[ ${FORCE:-0} -eq 0 ]]; then
    log "This will modify system settings. Create a backup first? [Y/n]"
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
      mkdir -p "$BACKUP_DIR"
      log "Creating settings backup in $BACKUP_DIR"
      run "adb -s \"$ADB_DEVICE\" pull /data/system/users/0/settings_global.xml \"$BACKUP_DIR/\""
      run "adb -s \"$ADB_DEVICE\" pull /data/system/users/0/settings_secure.xml \"$BACKUP_DIR/\""
      run "adb -s \"$ADB_DEVICE\" pull /data/system/users/0/settings_system.xml \"$BACKUP_DIR/\""
    fi
  fi
  
  # Battery optimizations
  log "Applying battery optimizations..."
  run "adb -s \"$ADB_DEVICE\" shell settings put global battery_saver_constants \
    \"vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,fullbackup_deferred=true,keyvaluebackup_deferred=true,gps_mode=low_power,data_saver=true,optional_sensors_disabled=true\""
  
  run "adb -s \"$ADB_DEVICE\" shell settings put global dynamic_power_savings_enabled 1"
  run "adb -s \"$ADB_DEVICE\" shell settings put global adaptive_battery_management_enabled 0"
  run "adb -s \"$ADB_DEVICE\" shell settings put global app_auto_restriction_enabled 1"
  run "adb -s \"$ADB_DEVICE\" shell settings put global app_restriction_enabled true"
  run "adb -s \"$ADB_DEVICE\" shell settings put global cached_apps_freezer enabled"
  
  # Network optimizations
  log "Applying network optimizations..."
  run "adb -s \"$ADB_DEVICE\" shell settings put global data_saver_mode 1"
  run "adb -s \"$ADB_DEVICE\" shell settings put global wifi_suspend_optimizations_enabled 2"
  run "adb -s \"$ADB_DEVICE\" shell settings put global ble_scan_always_enabled 0"
  run "adb -s \"$ADB_DEVICE\" shell settings put global wifi_scan_always_enabled 0"
  run "adb -s \"$ADB_DEVICE\" shell cmd netpolicy set restrict-background true"
  
  # Graphics and UI optimizations
  log "Applying graphics optimizations..."
  run "adb -s \"$ADB_DEVICE\" shell settings put global hw2d.force 1"
  run "adb -s \"$ADB_DEVICE\" shell settings put global hw3d.force 1"
  run "adb -s \"$ADB_DEVICE\" shell settings put global debug.sf.hw 1"
  run "adb -s \"$ADB_DEVICE\" shell settings put global debug.egl.hw 1"
  run "adb -s \"$ADB_DEVICE\" shell settings put global debug.enabletr true"
  
  # Reduce animations
  run "adb -s \"$ADB_DEVICE\" shell settings put global animator_duration_scale 0.5"
  run "adb -s \"$ADB_DEVICE\" shell settings put global transition_animation_scale 0.5"
  run "adb -s \"$ADB_DEVICE\" shell settings put global window_animation_scale 0.5"
  
  # Performance
  log "Applying performance optimizations..."
  run "adb -s \"$ADB_DEVICE\" shell settings put global sqlite_compatibility_wal_flags \"syncMode=OFF,fsyncMode=off\""
  
  # Run app compaction
  log "Optimizing app storage..."
  run "adb -s \"$ADB_DEVICE\" shell cmd device_config put activity_manager use_compaction true"
  
  # Optimize ART
  log "Optimizing ART..."
  run "adb -s \"$ADB_DEVICE\" shell cmd package compile -a -f -m speed-profile"
  
  log "Device optimization complete!"
}

# ----------------------------------------------------------------------
# Device Cleanup
# ----------------------------------------------------------------------
clean_device() {
  log "Cleaning device caches and temporary files..."
  check_adb_connection || return 1
  
  # Clear per-app caches
  log "Clearing app caches..."
  run "adb -s \"$ADB_DEVICE\" shell pm list packages -3 | cut -d: -f2 | xargs -r -n1 -I{} \
    adb -s \"$ADB_DEVICE\" shell pm clear --cache-only {}"
  
  # Trim system caches
  log "Trimming system caches..."
  run "adb -s \"$ADB_DEVICE\" shell pm trim-caches 128G"
  
  # Clear log files
  log "Clearing log files..."
  run "adb -s \"$ADB_DEVICE\" shell logcat -b all -c"
  
  # Delete temporary files
  log "Deleting temporary files..."
  run "adb -s \"$ADB_DEVICE\" shell 'find /sdcard -type f \( -name \"*.log\" -o -name \"*.tmp\" -o -name \"*.bak\" \) -delete'"
  
  # Run garbage collection
  log "Running garbage collection..."
  run "adb -s \"$ADB_DEVICE\" shell am broadcast -a android.intent.action.CLEAR_MEMORY"
  
  # Sync filesystems
  log "Syncing filesystems..."
  run "adb -s \"$ADB_DEVICE\" shell sync"
  
  # Run fstrim if supported
  log "Running fstrim if supported..."
  run "adb -s \"$ADB_DEVICE\" shell sm fstrim"
  
  log "Device cleanup complete!"
}

# ----------------------------------------------------------------------
# Usage and main function
# ----------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") COMMAND [OPTIONS]

Commands:
  optimize               Run performance optimizations on connected device
  clean                  Clean temporary files and cache on connected device
  backup                 Backup apps and settings from connected device
  optimize-apk FILE      Optimize an APK file
  optimize-image FILE    Optimize an image file
  install FILE           Install an APK on connected device
  uninstall PKG          Uninstall package from connected device
  help                   Show this help message

Options:
  -d, --device ID        Specify ADB device serial
  -o, --output PATH      Output path for optimized files
  -l, --lossy            Use lossy compression for optimization
  -n, --dry-run          Show commands without executing
  -v, --verbose          Enable verbose output

Examples:
  $(basename "$0") optimize
  $(basename "$0") optimize-apk -l -o output.apk input.apk
  $(basename "$0") optimize-image photo.jpg
EOF
}

parse_args() {
  COMMAND=""
  INPUT_FILE=""
  OUTPUT_FILE=""
  ADB_DEVICE=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--device)
        ADB_DEVICE="$2"
        shift 2
        ;;
      -o|--output)
        OUTPUT_FILE="$2"
        shift 2
        ;;
      -l|--lossy)
        LOSSY=1
        shift
        ;;
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -v|--verbose)
        DEBUG=1
        shift
        ;;
      help)
        usage
        exit 0
        ;;
      optimize|clean|backup|optimize-apk|optimize-image|install|uninstall)
        COMMAND="$1"
        shift
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
      *)
        if [[ -z "$INPUT_FILE" ]]; then
          INPUT_FILE="$1"
        else
          echo "Unexpected argument: $1" >&2
          usage
          exit 1
        fi
        shift
        ;;
    esac
  done
}

# ----------------------------------------------------------------------
# Main function
# ----------------------------------------------------------------------
main() {
  # Create log file
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  log "Starting Android Toolkit"
  
  # Parse arguments
  parse_args "$@"
  
  # Check for command
  if [[ -z "$COMMAND" ]]; then
    usage
    exit 1
  fi
  
  # Execute requested command
  case "$COMMAND" in
    optimize)
      optimize_device
      ;;
    clean)
      clean_device
      ;;
    backup)
      # Implement backup functionality
      log "Backup functionality not yet implemented"
      ;;
    optimize-apk)
      if [[ -z "$INPUT_FILE" ]]; then
        log "No APK file specified"
        usage
        exit 1
      fi
      optimize_apk "$INPUT_FILE" "${OUTPUT_FILE:-}"
      ;;
    optimize-image)
      if [[ -z "$INPUT_FILE" ]]; then
        log "No image file specified"
        usage
        exit 1
      fi
      optimize_image "$INPUT_FILE" "${OUTPUT_FILE:-}"
      ;;
    install)
      if [[ -z "$INPUT_FILE" ]]; then
        log "No APK file specified"
        usage
        exit 1
      fi
      check_adb_connection
      log "Installing $INPUT_FILE..."
      run "adb -s \"$ADB_DEVICE\" install -r \"$INPUT_FILE\""
      ;;
    uninstall)
      if [[ -z "$INPUT_FILE" ]]; then
        log "No package specified"
        usage
        exit 1
      fi
      check_adb_connection
      log "Uninstalling $INPUT_FILE..."
      run "adb -s \"$ADB_DEVICE\" uninstall \"$INPUT_FILE\""
      ;;
    *)
      log "Unknown command: $COMMAND"
      usage
      exit 1
      ;;
  esac
  
  # Clean up
  rm -rf "$TEMP_DIR"
  log "Android Toolkit completed"
}

# Run main function with all arguments
main "$@"
