#!/usr/bin/env bash
# android-toolkit.sh - Android device optimization and APK management toolkit
#
# Features:
# - Device optimization: battery, memory, network, graphics
# - APK optimization and repackaging
# - System cleanup and maintenance
# - Package management
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C

# --- Config & globals ---
readonly VERSION="1.0.0"
ADB_DEVICE=""
BACKUP_DIR="${HOME}/android_backup_$(date +%Y%m%d)"
LOG_FILE="/tmp/android-toolkit-$(date +%s).log"
TEMP_DIR=$(mktemp -d)
DRY_RUN=0
LOSSY=0
FORCE=0
OPERATION=""
APK_INPUT=""
APK_OUTPUT=""

# --- Keystore config for APK signing ---
KEYSTORE_PATH="${HOME}/.android/debug.keystore"
KEYSTORE_PASS="android"
KEY_ALIAS="androiddebugkey"
KEY_PASS="android"

# --- Exit codes ---
E_USAGE=64
E_DEPEND=65
E_DEVICE=66
E_ABORT=130

# --- Helpers ---
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }
log_info() { log "INFO: $1"; }
log_warn() { log "WARN: $1" >&2; }
log_error() { log "ERROR: $1" >&2; }

# Run command or print if in dry-run mode
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY_RUN] Would execute: $*"
    return 0
  fi
  
  if ! "$@" >>"$LOG_FILE" 2>&1; then
    log_error "Command failed: $*"
    log_error "Check log file for details: $LOG_FILE"
    return 1
  fi
  return 0
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "Required command \"$1\" not found."
    case "$1" in
      adb) log_error "Install Android SDK Platform Tools" ;;
      aapt*) log_error "Install Android SDK Build Tools" ;;
      zipalign|apksigner) log_error "Install Android SDK Build Tools" ;;
    esac
    exit "$E_DEPEND"
  }
}

check_adb_connection() {
  local device_count
  
  # Start ADB server if not running
  run adb start-server
  
  # Get connected devices
  if [[ -z "$ADB_DEVICE" ]]; then
    device_count=$(adb devices | grep -c -v "List of devices\|^$")
    
    if [[ $device_count -eq 0 ]]; then
      log_error "No Android devices found. Connect a device and try again."
      exit "$E_DEVICE"
    elif [[ $device_count -gt 1 ]]; then
      log_warn "Multiple devices found. Using first connected device."
      ADB_DEVICE=$(adb devices | grep -v "List of devices\|^$" | head -1 | awk '{print $1}')
      log_info "Selected device: $ADB_DEVICE"
    else
      ADB_DEVICE=$(adb devices | grep -v "List of devices\|^$" | awk '{print $1}')
    fi
  else
    if ! adb devices | grep -q "$ADB_DEVICE"; then
      log_error "Specified device '$ADB_DEVICE' not found."
      exit "$E_DEVICE"
    fi
  fi
  
  # Check if device is responsive
  if ! adb -s "$ADB_DEVICE" shell echo "Connection test" >/dev/null; then
    log_error "Device is not responding."
    exit "$E_DEVICE"
  fi
  
  log_info "Connected to device: $ADB_DEVICE"
  return 0
}

# --- Cleanup ---
cleanup() {
  log_info "Cleaning up temporary files..."
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# --- Usage ---
print_usage() {
  cat <<EOF
Android Toolkit v${VERSION} - Device optimization and APK management

USAGE:
  $(basename "$0") [OPTIONS] COMMAND [ARGS...]

COMMANDS:
  optimize            Run performance optimizations on connected device
  clean               Clean temporary files and cache on connected device
  backup              Backup apps and settings from connected device
  optimize-apk INPUT  Optimize an APK file
  install APK         Install an APK on connected device
  uninstall PKG       Uninstall package from connected device
  shell               Start an ADB shell session
  logcat              View device logs
  screenshot [PATH]   Take a screenshot

OPTIONS:
  -d, --device ID     Specify ADB device serial
  -n, --dry-run       Show commands without executing
  -f, --force         Skip confirmations
  -l, --lossy         Use lossy compression for APK optimization
  -o, --output PATH   Output path for files (screenshots, optimized APKs)
  -h, --help          Show this help message

EXAMPLES:
  $(basename "$0") optimize
  $(basename "$0") optimize-apk -l -o output.apk input.apk
  $(basename "$0") --device DEVICE_ID clean

EOF
  exit "$E_USAGE"
}

# --- APK Optimization ---
optimize_apk() {
  local input_apk="$1"
  local output_apk="${2:-${input_apk%.apk}-optimized.apk}"
  local tmpdir="${TEMP_DIR}/apk_opt"
  local decoded_dir="${tmpdir}/decoded"
  local build_dir="${tmpdir}/build"
  
  log_info "Optimizing APK: $input_apk -> $output_apk"
  
  # Check if the input APK exists
  if [[ ! -f "$input_apk" ]]; then
    log_error "Input APK not found: $input_apk"
    return 1
  fi
  
  # Required tools
  require_cmd zipalign
  require_cmd apksigner
  require_cmd aapt2
  
  mkdir -p "$decoded_dir" "$build_dir"
  
  # Step 1: Analyze the APK
  log_info "Analyzing APK..."
  run aapt2 dump badging "$input_apk"
  
  # Step 2: Optimize resources
  log_info "Optimizing resources..."
  
  # For images, we'll extract, optimize, and repack
  if command -v pngquant >/dev/null && [[ $LOSSY -eq 1 ]]; then
    log_info "Extracting and optimizing images..."
    run unzip -q "$input_apk" -d "$decoded_dir"
    
    # Optimize PNGs with pngquant (lossy)
    find "$decoded_dir" -name "*.png" -type f -print0 | xargs -0 -n1 -P "$(nproc)" bash -c '
      input="$1"
      if command -v pngquant >/dev/null; then
        pngquant --force --skip-if-larger --quality=65-85 --speed=1 --strip --output "${input}" -- "${input}"
      fi
    ' _ || true
    
    # Optimize JPGs with jpegoptim if available
    if command -v jpegoptim >/dev/null; then
      find "$decoded_dir" -name "*.jpg" -o -name "*.jpeg" -type f -print0 | xargs -0 -n1 -P "$(nproc)" bash -c '
        input="$1"
        if command -v jpegoptim >/dev/null; then
          jpegoptim --strip-all --max=85 -o -- "${input}"
        fi
      ' _ || true
    fi
    
    # Repack the APK
    log_info "Repacking optimized resources..."
    (cd "$decoded_dir" && zip -r -q "$build_dir/temp.apk" .)
    cp "$build_dir/temp.apk" "$build_dir/aligned.apk"
  else
    # Just copy for alignment step
    cp "$input_apk" "$build_dir/aligned.apk"
  fi
  
  # Step 3: Zipalign
  log_info "Aligning APK..."
  run zipalign -v -f -p 4 "$build_dir/aligned.apk" "$build_dir/aligned_fixed.apk"
  
  # Step 4: Sign the APK
  log_info "Signing APK..."
  if [[ ! -f "$KEYSTORE_PATH" ]]; then
    log_warn "Keystore not found. Creating debug keystore..."
    run keytool -genkey -v -keystore "$KEYSTORE_PATH" -storepass "$KEYSTORE_PASS" \
      -alias "$KEY_ALIAS" -keypass "$KEY_PASS" -keyalg RSA -keysize 2048 -validity 10000 \
      -dname "CN=Android Debug,O=Android,C=US"
  fi
  
  run apksigner sign --ks "$KEYSTORE_PATH" --ks-pass "pass:$KEYSTORE_PASS" \
    --ks-key-alias "$KEY_ALIAS" --key-pass "pass:$KEY_PASS" \
    --out "$output_apk" "$build_dir/aligned_fixed.apk"
  
  # Step 5: Verify
  log_info "Verifying APK..."
  run apksigner verify --verbose "$output_apk"
  
  # Compare sizes
  local orig_size input_size
  orig_size=$(stat -c "%s" "$input_apk")
  input_size=$(stat -c "%s" "$output_apk")
  local saved_kb saved_percent
  saved_kb=$(( (orig_size - input_size) / 1024 ))
  saved_percent=$(( (orig_size - input_size) * 100 / orig_size ))
  
  log_info "Optimization complete!"
  log_info "Original size: $(( orig_size / 1024 )) KB"
  log_info "New size: $(( input_size / 1024 )) KB"
  log_info "Saved: ${saved_kb} KB (${saved_percent}%)"
  
  return 0
}

# --- Device Optimization ---
optimize_device() {
  log_info "Running device optimization..."
  check_adb_connection
  
  # Create backup of current settings
  if [[ $FORCE -eq 0 ]]; then
    log_warn "This will modify system settings. Create a backup first? [Y/n]"
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
      mkdir -p "$BACKUP_DIR"
      log_info "Creating settings backup in $BACKUP_DIR"
      run adb -s "$ADB_DEVICE" pull /data/system/users/0/settings_global.xml "$BACKUP_DIR/"
      run adb -s "$ADB_DEVICE" pull /data/system/users/0/settings_secure.xml "$BACKUP_DIR/"
      run adb -s "$ADB_DEVICE" pull /data/system/users/0/settings_system.xml "$BACKUP_DIR/"
    fi
  fi
  
  # Battery optimizations
  log_info "Applying battery optimizations..."
  run adb -s "$ADB_DEVICE" shell settings put global battery_saver_constants \
    "vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,fullbackup_deferred=true,keyvaluebackup_deferred=true,gps_mode=low_power,data_saver=true,optional_sensors_disabled=true"
  
  run adb -s "$ADB_DEVICE" shell settings put global dynamic_power_savings_enabled 1
  run adb -s "$ADB_DEVICE" shell settings put global adaptive_battery_management_enabled 0
  run adb -s "$ADB_DEVICE" shell settings put global app_auto_restriction_enabled 1
  run adb -s "$ADB_DEVICE" shell settings put global app_restriction_enabled true
  run adb -s "$ADB_DEVICE" shell settings put global cached_apps_freezer enabled
  
  # Network optimizations
  log_info "Applying network optimizations..."
  run adb -s "$ADB_DEVICE" shell settings put global data_saver_mode 1
  run adb -s "$ADB_DEVICE" shell settings put global wifi_suspend_optimizations_enabled 2
  run adb -s "$ADB_DEVICE" shell settings put global ble_scan_always_enabled 0
  run adb -s "$ADB_DEVICE" shell settings put global wifi_scan_always_enabled 0
  run adb -s "$ADB_DEVICE" shell cmd netpolicy set restrict-background true
  
  # Graphics and UI optimizations
  log_info "Applying graphics optimizations..."
  run adb -s "$ADB_DEVICE" shell settings put global hw2d.force 1
  run adb -s "$ADB_DEVICE" shell settings put global hw3d.force 1
  run adb -s "$ADB_DEVICE" shell settings put global debug.sf.hw 1
  run adb -s "$ADB_DEVICE" shell settings put global debug.egl.hw 1
  run adb -s "$ADB_DEVICE" shell settings put global debug.enabletr true
  
  # Reduce animations
  run adb -s "$ADB_DEVICE" shell settings put global animator_duration_scale 0.5
  run adb -s "$ADB_DEVICE" shell settings put global transition_animation_scale 0.5
  run adb -s "$ADB_DEVICE" shell settings put global window_animation_scale 0.5
  
  # Performance
  log_info "Applying performance optimizations..."
  run adb -s "$ADB_DEVICE" shell settings put global sqlite_compatibility_wal_flags "syncMode=OFF,fsyncMode=off"
  
  # Run app compaction
  log_info "Optimizing app storage..."
  run adb -s "$ADB_DEVICE" shell cmd device_config put activity_manager use_compaction true
  
  # Optimize ART
  log_info "Optimizing ART..."
  run adb -s "$ADB_DEVICE" shell cmd package compile -a -f -m speed-profile
  
  log_info "Device optimization complete!"
}

# --- Device Cleanup ---
clean_device() {
  log_info "Cleaning device caches and temporary files..."
  check_adb_connection
  
  # Clear per-app caches
  log_info "Clearing app caches..."
  run adb -s "$ADB_DEVICE" shell pm list packages -3 | cut -d: -f2 | xargs -r -n1 -I{} \
    adb -s "$ADB_DEVICE" shell pm clear --cache-only {}
  
  # Trim system caches
  log_info "Trimming system caches..."
  run adb -s "$ADB_DEVICE" shell pm trim-caches 128G
  
  # Clear log files
  log_info "Clearing log files..."
  run adb -s "$ADB_DEVICE" shell logcat -b all -c
  
  # Delete temporary files
  log_info "Deleting temporary files..."
  run adb -s "$ADB_DEVICE" shell 'find /sdcard -type f \( -name "*.log" -o -name "*.tmp" -o -name "*.bak" \) -delete'
  
  # Run garbage collection
  log_info "Running garbage collection..."
  run adb -s "$ADB_DEVICE" shell am broadcast -a android.intent.action.CLEAR_MEMORY
  
  # Sync filesystems
  log_info "Syncing filesystems..."
  run adb -s "$ADB_DEVICE" shell sync
  
  # Run fstrim if supported
  log_info "Running fstrim if supported..."
  run adb -s "$ADB_DEVICE" shell sm fstrim
  
  log_info "Device cleanup complete!"
}

# --- Device Backup ---
backup_device() {
  log_info "Starting device backup..."
  check_adb_connection
  
  local backup_dir="${BACKUP_DIR}/$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$backup_dir/apps" "$backup_dir/settings"
  
  # Backup settings
  log_info "Backing up settings..."
  run adb -s "$ADB_DEVICE" pull /data/system/users/0/settings_global.xml "$backup_dir/settings/"
  run adb -s "$ADB_DEVICE" pull /data/system/users/0/settings_secure.xml "$backup_dir/settings/"
  run adb -s "$ADB_DEVICE" pull /data/system/users/0/settings_system.xml "$backup_dir/settings/"
  
  # Get list of installed packages
  log_info "Backing up package list..."
  run adb -s "$ADB_DEVICE" shell pm list packages -3 > "$backup_dir/user_package_list.txt"
  run adb -s "$ADB_DEVICE" shell pm list packages -s > "$backup_dir/system_package_list.txt"
  
  # Backup APKs of user apps
  log_info "Backing up user apps (this may take a while)..."
  while read -r pkg_line; do
    pkg="${pkg_line#package:}"
    [[ -z "$pkg" ]] && continue
    
    log_info "Backing up $pkg..."
    apk_path=$(run adb -s "$ADB_DEVICE" shell pm path "$pkg" | head -n1)
    apk_path="${apk_path#package:}"
    
    if [[ -z "$apk_path" ]]; then
      log_warn "Couldn't find APK path for $pkg"
      continue
    fi
    
    run adb -s "$ADB_DEVICE" pull "$apk_path" "$backup_dir/apps/${pkg}.apk"
  done < <(run adb -s "$ADB_DEVICE" shell pm list packages -3)
  
  log_info "Backup complete: $backup_dir"
}

# --- Take Screenshot ---
take_screenshot() {
  local output_path="${1:-/sdcard/screenshot_$(date +%Y%m%d_%H%M%S).png}"
  local local_path="${output_path#/sdcard/}"
  
  if [[ "$local_path" == "$output_path" ]]; then
    # Not a path on the device, assume it's a local path
    local_path="$output_path"
    output_path="/sdcard/temp_screenshot.png"
  fi
  
  log_info "Taking screenshot..."
  check_adb_connection
  
  run adb -s "$ADB_DEVICE" shell screencap -p "$output_path"
  run adb -s "$ADB_DEVICE" pull "$output_path" "$local_path"
  
  if [[ "$output_path" == "/sdcard/temp_screenshot.png" ]]; then
    run adb -s "$ADB_DEVICE" shell rm "$output_path"
  fi
  
  log_info "Screenshot saved to $local_path"
}

# --- Main Command Handler ---
handle_command() {
  case "$OPERATION" in
    optimize)
      optimize_device
      ;;
    clean)
      clean_device
      ;;
    backup)
      backup_device
      ;;
    optimize-apk)
      [[ -z "$APK_INPUT" ]] && { log_error "No input APK specified"; print_usage; }
      optimize_apk "$APK_INPUT" "$APK_OUTPUT"
      ;;
    install)
      [[ -z "$APK_INPUT" ]] && { log_error "No APK specified"; print_usage; }
      check_adb_connection
      log_info "Installing $APK_INPUT..."
      run adb -s "$ADB_DEVICE" install -r "$APK_INPUT"
      ;;
    uninstall)
      [[ -z "$APK_INPUT" ]] && { log_error "No package specified"; print_usage; }
      check_adb_connection
      log_info "Uninstalling $APK_INPUT..."
      run adb -s "$ADB_DEVICE" uninstall "$APK_INPUT"
      ;;
    shell)
      check_adb_connection
      log_info "Starting shell on device $ADB_DEVICE..."
      # Don't use run() here, we want an interactive shell
      adb -s "$ADB_DEVICE" shell
      ;;
    logcat)
      check_adb_connection
      log_info "Starting logcat for device $ADB_DEVICE..."
      # Don't use run() here, we want an interactive logcat
      adb -s "$ADB_DEVICE" logcat
      ;;
    screenshot)
      take_screenshot "$APK_OUTPUT"
      ;;
    *)
      log_error "Unknown operation: $OPERATION"
      print_usage
      ;;
  esac
}

# --- Main ---
main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--device)
        ADB_DEVICE="$2"
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -f|--force)
        FORCE=1
        shift
        ;;
      -l|--lossy)
        LOSSY=1
        shift
        ;;
      -o|--output)
        APK_OUTPUT="$2"
        shift 2
        ;;
      -h|--help)
        print_usage
        ;;
      -*)
        log_error "Unknown option: $1"
        print_usage
        ;;
      *)
        if [[ -z "$OPERATION" ]]; then
          OPERATION="$1"
          shift
        elif [[ -z "$APK_INPUT" ]]; then
          APK_INPUT="$1"
          shift
        else
          log_error "Too many arguments: $1"
          print_usage
        fi
        ;;
    esac
  done
  
  # Validate arguments
  [[ -z "$OPERATION" ]] && print_usage
  
  # Create log file
  touch "$LOG_FILE"
  log_info "Starting Android Toolkit v${VERSION}"
  log_info "Log file: $LOG_FILE"
  
  # Handle the command
  handle_command
  
  log_info "Operation completed successfully."
  exit 0
}

main "$@"