#!/usr/bin/env bash
# android-toolkit-clean.sh - Android device cleanup and maintenance
#
# Features:
# - Clear app caches and dalvik-cache
# - Remove temporary and junk files
#   - Added: Thumbs.db, .DS_Store, .~* patterns
# - Optimize ART/dalvik
# - Clean up logs and system caches
# - Free disk space
#
# Usage: ./android-toolkit-clean.sh [OPTIONS]
#   -a, --all            Run all cleanup operations
#   -c, --cache          Clean app caches only
#   -l, --logs           Clear logs only
#   -t, --temp           Remove temporary files only
#   -d, --device ID      Target specific device (if multiple connected)
#   -i, --interactive    Show interactive menu (default if no args)
#   -y, --yes            Skip confirmations
#   -v, --verbose        Show detailed output
#   -h, --help           Show this help

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C

# --- Constants and globals ---
VERSION="1.0.0"
SCRIPT_NAME="${0##*/}"
ASSUME_YES=0
VERBOSE=0
DEVICE=""

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper functions ---
log() {
  local level="$1"
  shift
  case "$level" in
  info) printf "${GREEN}[INFO]${NC} %s\n" "$*" ;;
  warn) printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2 ;;
  error) printf "${RED}[ERROR]${NC} %s\n" "$*" >&2 ;;
  debug) [[ $VERBOSE -eq 1 ]] && printf "${BLUE}[DEBUG]${NC} %s\n" "$*" ;;
  esac
}

check_deps() {
  local missing=()
  for cmd in adb; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log error "Missing required dependencies: ${missing[*]}"
    if command -v pacman &>/dev/null; then
      log info "Install with: sudo pacman -S --needed android-tools"
    elif command -v apt &>/dev/null; then
      log info "Install with: sudo apt install -y android-tools-adb"
    elif command -v pkg &>/dev/null; then
      log info "Install with: pkg install android-tools"
    fi
    exit 1
  fi
}

check_adb_connection() {
  if ! adb get-state &>/dev/null; then
    log error "No device connected or unauthorized. Please connect a device and enable USB debugging."
    exit 1
  fi

  if [[ -n $DEVICE ]]; then
    # Use the specific device
    ADB_CMD=("adb" "-s" "$DEVICE")
    log debug "Using device: $DEVICE"
  else
    local devices
    mapfile -t devices < <(adb devices | grep -v "^List" | grep -v "^$" | cut -f1)

    if [[ ${#devices[@]} -eq 0 ]]; then
      log error "No devices connected"
      exit 1
    elif [[ ${#devices[@]} -gt 1 ]]; then
      log warn "Multiple devices found, using first device: ${devices[0]}"
      DEVICE="${devices[0]}"
      ADB_CMD=("adb" "-s" "$DEVICE")
    else
      DEVICE="${devices[0]}"
      ADB_CMD=("adb")
      log debug "Using device: $DEVICE"
    fi
  fi
}

run_adb() {
  local cmd=("${ADB_CMD[@]}" "$@")
  log debug "Running: ${cmd[*]}"
  if [[ $VERBOSE -eq 1 ]]; then
    "${cmd[@]}"
  else
    "${cmd[@]}" >/dev/null 2>&1 || {
      local rc=$?
      log error "Command failed: ${cmd[*]}"
      return "$rc"
    }
  fi
}

confirm() {
  if [[ $ASSUME_YES -eq 1 ]]; then
    return 0
  fi

  local prompt="$1"
  local default="${2:-n}"
  local yn="y/N"
  [[ $default == "y" ]] && yn="Y/n"

  read -r -p "$prompt [$yn] " answer
  answer=${answer:-$default}
  [[ ${answer,,} == "y"* ]]
}

get_free_space() {
  run_adb shell "df -h /data | tail -n1 | awk '{print \$4}'" | tr -d '\r'
}

# --- Cleanup functions ---

clean_app_caches() {
  log info "Cleaning app caches..."

  # Get storage info before cleaning
  local space_before
  space_before=$(get_free_space)
  log info "Free space before cleaning: $space_before"

  # Clear per-app cache (third-party apps)
  log info "Clearing per-app cache (third-party apps)..."

  # Get package list first
  local third_party_packages
  mapfile -t third_party_packages < <(run_adb shell "pm list packages -3" | sed 's/^package://g')

  if [[ ${#third_party_packages[@]} -gt 0 ]]; then
    for pkg in "${third_party_packages[@]}"; do
      log debug "Clearing cache for $pkg"
      run_adb shell "pm clear --cache-only ${pkg}"
    done
    log info "Cleared caches for ${#third_party_packages[@]} third-party apps"
  else
    log warn "No third-party apps found"
  fi

  # Also clear system app caches for thoroughness
  log info "Clearing system app caches..."
  local system_packages
  mapfile -t system_packages < <(run_adb shell "pm list packages -s" | sed 's/^package://g')

  if [[ ${#system_packages[@]} -gt 0 ]]; then
    for pkg in "${system_packages[@]}"; do
      run_adb shell "pm clear --cache-only ${pkg}"
    done
    log info "Cleared caches for ${#system_packages[@]} system apps"
  fi

  # Trim overall caches
  log info "Trimming system-wide app caches..."
  run_adb shell "pm trim-caches 128G"

  # Get storage info after cleaning
  local space_after
  space_after=$(get_free_space)
  log info "Free space after cleaning: $space_after"
  log info "App cache cleanup complete"
}

clean_logs() {
  log info "Cleaning system logs..."

  # Clear various log buffers
  run_adb shell "logcat -b all -c"
  run_adb shell "logcat -c"

  # Set log size limits
  run_adb shell "logcat -G 128K -b main -b system"
  run_adb shell "logcat -G 64K -b radio -b events -b crash"

  # Disable various logging
  run_adb shell "cmd display ab-logging-disable"
  run_adb shell "cmd display dwb-logging-disable"
  run_adb shell "cmd display dmd-logging-disable"
  run_adb shell "looper_stats disable"
  run_adb shell "dumpsys power set_sampling_rate 0"

  # Clear battery stats
  run_adb shell "dumpsys batterystats --reset"

  # Clean crash reports and coredumps
  run_adb shell "rm -rf /data/tombstones/* /data/anr/*" || log warn "Failed to clean some system log files (likely requires root)"

  log info "Log cleanup complete"
}

clean_temp_files() {
  log info "Cleaning temporary and junk files..."

  # Find and delete common temporary file patterns (updated with additional patterns)
  run_adb shell "find /sdcard -type f \( \
    -iname \"*.tmp\" -o \
    -iname \"*.temp\" -o \
    -iname \"*.crdownload\" -o \
    -iname \"*.partial\" -o \
    -iname \"*.log\" -o \
    -iname \"*.bak\" -o \
    -iname \"*.old\" -o \
    -iname \"~*\" -o \
    -iname \".~*\" -o \
    -iname \"Thumbs.db\" -o \
    -iname \".DS_Store\" \
  \) -delete"

  # For each external storage volume, clean temp files
  local storage_paths
  mapfile -t storage_paths < <(run_adb shell "ls /storage" | grep -v "self\|emulated\|^$")

  if [[ ${#storage_paths[@]} -gt 0 ]]; then
    for path in "${storage_paths[@]}"; do
      log info "Cleaning temporary files from /storage/$path"
      run_adb shell "find /storage/$path -type f \( \
        -iname \"*.tmp\" -o \
        -iname \"*.temp\" -o \
        -iname \"*.crdownload\" -o \
        -iname \"*.partial\" -o \
        -iname \"*.log\" -o \
        -iname \"*.bak\" -o \
        -iname \"*.old\" -o \
        -iname \"~*\" -o \
        -iname \".~*\" -o \
        -iname \"Thumbs.db\" -o \
        -iname \".DS_Store\" \
      \) -delete"
    done
  fi

  # Remove empty directories
  log info "Removing empty directories..."
  run_adb shell "find /sdcard -type d -empty -delete"

  for path in "${storage_paths[@]:-}"; do
    run_adb shell "find /storage/$path -type d -empty -delete"
  done

  log info "Temporary file cleanup complete"
}

clean_browser_cache() {
  log info "Cleaning browser caches..."

  # Chrome/Browser cache
  run_adb shell "rm -rf /sdcard/Android/data/com.android.chrome/cache/*"
  run_adb shell "rm -rf /sdcard/Android/data/com.android.browser/cache/*"
  run_adb shell "rm -rf /sdcard/Android/data/com.sec.android.browser/cache/*"

  # Firefox cache
  run_adb shell "rm -rf /sdcard/Android/data/org.mozilla.firefox/cache/*"
  run_adb shell "rm -rf /data/data/org.mozilla.firefox/cache/*"

  # WebView cache
  run_adb shell "rm -rf /sdcard/Android/data/com.google.android.webview/cache/*"
  run_adb shell "rm -rf /sdcard/Android/data/com.android.webview/cache/*"

  log info "Browser cache cleanup complete"
}

clean_thumbnails() {
  log info "Cleaning media thumbnails..."

  # Thumbnail caches
  run_adb shell "rm -rf /sdcard/DCIM/.thumbnails/*"
  run_adb shell "rm -rf /sdcard/Pictures/.thumbnails/*"
  run_adb shell "rm -rf /sdcard/.thumbnails/*"
  run_adb shell "rm -rf /sdcard/Android/data/com.android.providers.media/albumthumbs/*"

  # Clear media scanner databases
  run_adb shell "rm -f /sdcard/Android/data/com.android.providers.media/databases/*.db-wal"
  run_adb shell "rm -f /sdcard/Android/data/com.android.providers.media/databases/*.db-shm"

  log info "Thumbnail cleanup complete"
}

optimize_art_runtime() {
  log info "Optimizing Android Runtime..."

  # Force package compilation/optimization
  run_adb shell "cmd package compile -m speed-profile -a"
  run_adb shell "cmd package compile -m speed -f -a"

  # Clean ART profiles
  run_adb shell "pm art cleanup"

  # Force dexopt jobs
  run_adb shell "pm bg-dexopt-job"

  # Run idle maintenance
  run_adb shell "cmd activity idle-maintenance"

  log info "ART runtime optimization complete"
}

clean_downloads() {
  log info "Cleaning downloads and media caches..."

  # Show downloads before cleaning
  log debug "Current downloads:"
  run_adb shell "ls -la /sdcard/Download/"

  # Ask for confirmation before cleaning downloads (updated to 45 days as per command)
  if confirm "Clean downloaded files older than 45 days? This will permanently delete files."; then
    run_adb shell "find /sdcard/Download/ -type f -mtime +45 -delete"
    log info "Cleaned old downloads"
  else
    log info "Skipping downloads cleanup"
  fi

  # Clean media caches for various apps
  run_adb shell "rm -rf /sdcard/Android/data/*/cache/*"

  log info "Downloads and media cache cleanup complete"
}

clean_app_data_folders() {
  log info "Cleaning application data folders..."

  # Remove .nomedia, .thumbs, etc from app data folders
  run_adb shell "find /sdcard/Android/data/*/files/ -type f -name '*.nomedia' -delete"

  # Clean .Trash folders in app data
  run_adb shell "rm -rf /sdcard/Android/data/*/files/.Trash/*"

  # Add app-specific cleanup patterns here

  # Clean WhatsApp media
  if confirm "Clean WhatsApp received media older than 30 days?"; then
    run_adb shell "find /sdcard/Android/data/com.whatsapp/files/ -type f -mtime +30 -delete" || log debug "WhatsApp media not found or can't access"
  fi

  log info "App data folders cleaned"
}

show_stats() {
  log info "Device storage statistics:"

  # Show overall storage
  run_adb shell "df -h /data"

  # Show top 10 apps by storage usage
  log info "Top 10 apps by storage usage:"
  run_adb shell "du -h /data/data | sort -hr | head -10"

  # Show top 10 largest files
  log info "Top 10 largest files in Download and DCIM:"
  run_adb shell "find /sdcard/Download /sdcard/DCIM -type f -exec ls -la {} \; | sort -k5nr | head -10"
}

run_full_cleanup() {
  log info "Running full device cleanup..."

  # Run all cleanup functions
  clean_app_caches
  clean_logs
  clean_temp_files
  clean_browser_cache
  clean_thumbnails
  optimize_art_runtime

  # Optional cleanups requiring confirmation
  if confirm "Clean downloads and app data folders?"; then
    clean_downloads
    clean_app_data_folders
  fi

  # Show final stats
  show_stats

  log info "Full cleanup complete!"
}

# --- Menu and UI functions ---

# Print usage information
usage() {
  cat <<EOF
${CYAN}Android Toolkit: Clean & Maintain v${VERSION}${NC}

${YELLOW}Usage:${NC} $SCRIPT_NAME [OPTIONS]

${YELLOW}Options:${NC}
  -a, --all            Run all cleanup operations
  -c, --cache          Clean app caches only
  -l, --logs           Clear logs only
  -t, --temp           Remove temporary files only
  -d, --device ID      Target specific device (if multiple connected)
  -i, --interactive    Show interactive menu (default if no args)
  -y, --yes            Skip confirmations
  -v, --verbose        Show detailed output
  -h, --help           Show this help

${YELLOW}Examples:${NC}
  $SCRIPT_NAME --all
  $SCRIPT_NAME -c -l
  $SCRIPT_NAME -i
  $SCRIPT_NAME --cache --device emulator-5554
EOF
}

show_interactive_menu() {
  # Check terminal capabilities
  if [[ ! -t 1 ]]; then
    log error "Interactive menu requires a terminal"
    exit 1
  fi

  # Try to use dialog if available, otherwise use plain read
  if command -v dialog &>/dev/null; then
    use_dialog_menu
  else
    use_plain_menu
  fi
}

use_dialog_menu() {
  local choice

  while true; do
    choice=$(dialog --clear --backtitle "Android Toolkit: Clean & Maintain v${VERSION}" \
      --title "Main Menu" --menu "Select a cleaning option:" 20 60 10 \
      "1" "Full cleanup (all options)" \
      "2" "Clean app caches" \
      "3" "Clear logs" \
      "4" "Clean temporary files" \
      "5" "Clean browser caches" \
      "6" "Clean thumbnails" \
      "7" "Optimize ART runtime" \
      "8" "Clean downloads folder" \
      "9" "Show storage statistics" \
      "q" "Quit" \
      3>&1 1>&2 2>&3)

    clear

    case "$choice" in
    1) run_full_cleanup ;;
    2) clean_app_caches ;;
    3) clean_logs ;;
    4) clean_temp_files ;;
    5) clean_browser_cache ;;
    6) clean_thumbnails ;;
    7) optimize_art_runtime ;;
    8) clean_downloads ;;
    9) show_stats ;;
    q | "") break ;;
    esac
  done
}

use_plain_menu() {
  local choice

  while true; do
    echo -e "${CYAN}=== Android Toolkit: Clean & Maintain v${VERSION} ===${NC}"
    echo -e "${YELLOW}1)${NC} Full cleanup (all options)"
    echo -e "${YELLOW}2)${NC} Clean app caches"
    echo -e "${YELLOW}3)${NC} Clear logs"
    echo -e "${YELLOW}4)${NC} Clean temporary files"
    echo -e "${YELLOW}5)${NC} Clean browser caches"
    echo -e "${YELLOW}6)${NC} Clean thumbnails"
    echo -e "${YELLOW}7)${NC} Optimize ART runtime"
    echo -e "${YELLOW}8)${NC} Clean downloads folder"
    echo -e "${YELLOW}9)${NC} Show storage statistics"
    echo -e "${YELLOW}q)${NC} Quit"
    echo
    read -r -p "Select an option: " choice

    case "$choice" in
    1) run_full_cleanup ;;
    2) clean_app_caches ;;
    3) clean_logs ;;
    4) clean_temp_files ;;
    5) clean_browser_cache ;;
    6) clean_thumbnails ;;
    7) optimize_art_runtime ;;
    8) clean_downloads ;;
    9) show_stats ;;
    q | Q) break ;;
    *) echo -e "${RED}Invalid option${NC}" ;;
    esac

    echo
  done
}

# --- Parse arguments ---
parse_args() {
  local DO_ALL=0
  local DO_CACHE=0
  local DO_LOGS=0
  local DO_TEMP=0
  local INTERACTIVE=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -a | --all)
      DO_ALL=1
      shift
      ;;
    -c | --cache)
      DO_CACHE=1
      shift
      ;;
    -l | --logs)
      DO_LOGS=1
      shift
      ;;
    -t | --temp)
      DO_TEMP=1
      shift
      ;;
    -d | --device)
      DEVICE="$2"
      shift 2
      ;;
    -i | --interactive)
      INTERACTIVE=1
      shift
      ;;
    -y | --yes)
      ASSUME_YES=1
      shift
      ;;
    -v | --verbose)
      VERBOSE=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      log error "Unknown option: $1"
      usage
      exit 1
      ;;
    esac
  done

  # If no options are specified, default to interactive mode
  if [[ $DO_ALL -eq 0 && $DO_CACHE -eq 0 && $DO_LOGS -eq 0 && $DO_TEMP -eq 0 && $INTERACTIVE -eq 0 ]]; then
    INTERACTIVE=1
  fi

  # Execute specified operations
  if [[ $DO_ALL -eq 1 ]]; then
    run_full_cleanup
  else
    [[ $DO_CACHE -eq 1 ]] && clean_app_caches
    [[ $DO_LOGS -eq 1 ]] && clean_logs
    [[ $DO_TEMP -eq 1 ]] && clean_temp_files
  fi

  if [[ $INTERACTIVE -eq 1 ]]; then
    show_interactive_menu
  fi
}

main() {
  # Check dependencies
  check_deps

  # Banner
  echo -e "${CYAN}=================================================${NC}"
  echo -e "${CYAN}  Android Toolkit: Clean & Maintain v${VERSION}${NC}"
  echo -e "${CYAN}=================================================${NC}"
  echo

  # Check device connection
  check_adb_connection
  log info "Connected to device: $DEVICE"

  # Show device info
  local device_model
  device_model=$(run_adb shell "getprop ro.product.model" | tr -d '\r')
  local android_version
  android_version=$(run_adb shell "getprop ro.build.version.release" | tr -d '\r')
  log info "Device: $device_model (Android $android_version)"

  # Parse command line args and run appropriate functions
  parse_args "$@"

  log info "All operations complete"
}

main "$@"
