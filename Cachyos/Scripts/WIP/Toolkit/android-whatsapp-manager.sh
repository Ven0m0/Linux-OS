#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C
cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" &>/dev/null || exit 1

# --- Configuration ---
DELETE_DAYS=90
OPUS_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio"
  "/sdcard/Music/WhatsApp Audio"
)
IMAGE_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images"
  "/sdcard/DCIM/Camera"
  "/sdcard/Pictures"
)
DELETE_ALL_PATHS=(
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp AI Media"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Bug Report Attachments"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Sticker Packs"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Stickers"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Backup Excluded Stickers"
  "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Profile Photos"
)
TEMP_DIR="/data/local/tmp/optimization"
DRYRUN=0
VERBOSE=0
USE_SHIZUKU=0
JOBS="$(nproc 2>/dev/null || echo 4)"

# --- Helper functions ---
has(){ command -v "$1" &>/dev/null; }

log(){
  local level="$1"; shift
  case "$level" in
    info)  printf "\033[0;32m[INFO]\033[0m %s\n" "$*" ;;
    warn)  printf "\033[0;33m[WARN]\033[0m %s\n" "$*" >&2 ;;
    error) printf "\033[0;31m[ERROR]\033[0m %s\n" "$*" >&2 ;;
    debug) [[ $VERBOSE -eq 1 ]] && printf "\033[0;34m[DEBUG]\033[0m %s\n" "$*" ;;
  esac
}

run_cmd() {
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    if [[ $DRYRUN -eq 1 ]]; then
      log debug "Would run: rish $*"
      return 0
    fi
    rish "$@"
  else
    if [[ $DRYRUN -eq 1 ]]; then
      log debug "Would run: adb shell $*"
      return 0
    fi
    adb shell "$@"
  fi
}

check_requirements() {
  if [[ $USE_SHIZUKU -eq 1 ]]; then
    has rish || { log error "rish command not found. Install Shizuku and set up rish."; exit 1; }
    # Test rish connection
    rish id >/dev/null 2>&1 || { log error "rish connection failed. Is Shizuku running?"; exit 1; }
  else
    has adb || { log error "adb command not found. Install Android SDK Platform Tools."; exit 1; }
    # Test adb connection
    adb get-state >/dev/null 2>&1 || { log error "No device connected via adb."; exit 1; }
  fi
}

# --- Clean old opus files ---
clean_old_opus() {
  log info "Cleaning opus files older than $DELETE_DAYS days..."
  
  for path in "${OPUS_PATHS[@]}"; do
    log info "Processing: $path"
    # Properly handle spaces in paths
    escaped_path="${path// /\\ }"
    
    # First list files that match the criteria (for reporting)
    if [[ $VERBOSE -eq 1 ]]; then
      run_cmd "find \"$path\" -type f -name \"*.opus\" -mtime +$DELETE_DAYS -exec ls -la {} \;" | while read -r file_info; do
        log debug "Found: $file_info"
      done
    fi
    
    # Now delete the files
    if [[ $DRYRUN -eq 0 ]]; then
      run_cmd "find \"$path\" -type f -name \"*.opus\" -mtime +$DELETE_DAYS -delete"
      log info "Deleted opus files in $path older than $DELETE_DAYS days"
    else
      count=$(run_cmd "find \"$path\" -type f -name \"*.opus\" -mtime +$DELETE_DAYS | wc -l")
      log info "Would delete $count opus files in $path older than $DELETE_DAYS days"
    fi
  done
}

# --- Clean specific paths completely ---
clean_specific_paths() {
  log info "Cleaning specific WhatsApp folders completely..."
  
  for path in "${DELETE_ALL_PATHS[@]}"; do
    log info "Processing: $path"
    escaped_path="${path// /\\ }"
    
    if [[ $DRYRUN -eq 0 ]]; then
      run_cmd "rm -rf \"$path/\"*"
      log info "Deleted all files in $path"
    else
      count=$(run_cmd "find \"$path\" -type f | wc -l")
      log info "Would delete $count files in $path"
    fi
  done
}

# --- Optimize images ---
optimize_images() {
  log info "Setting up image optimization environment..."
  
  # Create temp directory on device
  run_cmd "mkdir -p \"$TEMP_DIR\""
  
  # Process each image path
  for path in "${IMAGE_PATHS[@]}"; do
    log info "Processing images in: $path"
    
    # First deduplicate images with fclones
    if run_cmd "[ -x /data/data/com.termux/files/usr/bin/fclones ]"; then
      log info "Running deduplication with fclones..."
      
      if [[ $DRYRUN -eq 0 ]]; then
        # Find groups of duplicate images
        run_cmd "/data/data/com.termux/files/usr/bin/fclones group -r \"$path\" --threads $JOBS"
        # Remove duplicates keeping the oldest
        run_cmd "/data/data/com.termux/files/usr/bin/fclones dedupe --strategy=oldestrandom \"$path\""
      else
        # Just count duplicates in dry run mode
        dupe_count=$(run_cmd "/data/data/com.termux/files/usr/bin/fclones group -r \"$path\" --count --json | grep -o '\"count\":[0-9]*' | cut -d: -f2")
        log info "Would deduplicate approximately $dupe_count images"
      fi
    else
      log warn "fclones not found on device, skipping deduplication"
    fi
    
    # Optimize images with available tools
    log info "Optimizing images..."
    if [[ $DRYRUN -eq 0 ]]; then
      # Check for available optimization tools in preference order
      if run_cmd "[ -x /data/data/com.termux/files/usr/bin/rimage ]"; then
        log info "Using rimage for optimization"
        run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) -exec /data/data/com.termux/files/usr/bin/rimage -i {} -o {} \\;"
      elif run_cmd "[ -x /data/data/com.termux/files/usr/bin/flaca ]"; then
        log info "Using flaca for optimization"
        run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) -exec /data/data/com.termux/files/usr/bin/flaca {} \\;"
      elif run_cmd "[ -x /data/data/com.termux/files/usr/bin/compresscli ]"; then
        log info "Using compresscli for optimization"
        run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) -exec /data/data/com.termux/files/usr/bin/compresscli {} \\;"
      elif run_cmd "[ -x /data/data/com.termux/files/usr/bin/imgc ]"; then
        log info "Using imgc for optimization"
        run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) -exec /data/data/com.termux/files/usr/bin/imgc {} \\;"
      else
        log warn "No image optimization tools found on device"
      fi
    else
      img_count=$(run_cmd "find \"$path\" -type f \\( -name \"*.jpg\" -o -name \"*.jpeg\" -o -name \"*.png\" \\) | wc -l")
      log info "Would optimize $img_count images"
    fi
  done
  
  # Clean up
  if [[ $DRYRUN -eq 0 ]]; then
    run_cmd "rm -rf \"$TEMP_DIR\""
  fi
}

# --- Main function ---
main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--shizuku) USE_SHIZUKU=1; shift ;;
      -n|--dry-run) DRYRUN=1; shift ;;
      -v|--verbose) VERBOSE=1; shift ;;
      -d|--days) DELETE_DAYS="$2"; shift 2 ;;
      -j|--jobs) JOBS="$2"; shift 2 ;;
      -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  -s, --shizuku    Use Shizuku (rish) instead of adb"
        echo "  -n, --dry-run    Show what would be done without actually doing it"
        echo "  -v, --verbose    Show verbose output"
        echo "  -d, --days DAYS  Delete files older than DAYS days (default: $DELETE_DAYS)"
        echo "  -j, --jobs JOBS  Number of parallel jobs (default: auto)"
        echo "  -h, --help       Show this help message"
        exit 0
        ;;
      *) log error "Unknown option: $1"; exit 1 ;;
    esac
  done
  
  log info "Android WhatsApp Media Manager v1.0"
  log info "Configuration:"
  log info "- Delete days: $DELETE_DAYS"
  log info "- Using: $(if [[ $USE_SHIZUKU -eq 1 ]]; then echo "Shizuku (rish)"; else echo "ADB"; fi)"
  log info "- Jobs: $JOBS"
  [[ $DRYRUN -eq 1 ]] && log info "- Dry run: Yes"
  
  # Check requirements
  check_requirements
  
  # Run the cleanup operations
  clean_old_opus
  clean_specific_paths
  optimize_images
  
  log info "All tasks completed successfully!"
}

main "$@"
