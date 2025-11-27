#!/usr/bin/env bash
# media-optimizer.sh - Comprehensive media optimization toolkit
#
# Features:
# - Smart image compression to WebP (with fallbacks)
# - Video transcoding to AV1 using SVT-AV1-Essential
# - Deduplication to save storage space
# - Multi-threaded processing for performance
# - Intelligent format selection based on content

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C

# Configuration (overridable via environment variables)
: "${MEDIA_OPT_QUALITY:=auto}"     # auto, lossless, lossy-low, lossy-medium, lossy-high
: "${MEDIA_OPT_THREADS:=$(nproc)}" # Number of threads to use
: "${MEDIA_OPT_BACKUP:=1}"         # Create backups of original files
: "${MEDIA_OPT_RECURSIVE:=0}"      # Process directories recursively
: "${MEDIA_OPT_WEBP_QUALITY:=80}"  # WebP quality (0-100)
: "${MEDIA_OPT_AV1_PRESET:=6}"     # SVT-AV1 preset (0-13, lower=better quality, slower)
: "${MEDIA_OPT_AV1_CRF:=30}"       # Constant Rate Factor for AV1 (0-63, lower=better)
: "${MEDIA_OPT_DEDUPE:=1}"         # Enable deduplication
: "${MEDIA_OPT_KEEP_EXIF:=1}"      # Preserve image metadata
: "${XDG_CACHE_HOME:=$HOME/.cache}"

# Directories and logging
SCRIPT_NAME="${0##*/}"
CACHE_DIR="${XDG_CACHE_HOME}/media-optimizer"
LOG_FILE="${CACHE_DIR}/optimizer.log"
BACKUP_DIR=""
mkdir -p "$CACHE_DIR"

# Terminal colors
if [[ -t 1 ]]; then
  RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MAG=$'\e[35m' CYN=$'\e[36m' RST=$'\e[0m'
else
  RED="" GRN="" YLW="" BLU="" MAG="" CYN="" RST=""
fi

# Helper functions
log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1" | tee -a "$LOG_FILE"; }
log_debug(){ [[ ${MEDIA_OPT_DEBUG:-0} -eq 1 ]] && printf '[DEBUG %s] %s\n' "$(date +%H:%M:%S)" "$1" | tee -a "$LOG_FILE"; }
log_err(){ printf '[ERROR %s] %s\n' "$(date +%H:%M:%S)" "$1" | tee -a "$LOG_FILE" >&2; }

file_size(){
  stat -c "%s" "$1" 2>/dev/null || stat -f "%z" "$1" 2>/dev/null || echo 0
}

human_size(){
  local bytes="$1" scale=0
  local units=("B" "KB" "MB" "GB" "TB")

  while ((bytes > 1024)); do
    bytes=$((bytes / 1024))
    ((scale++))
  done

  printf "%d %s" "$bytes" "${units[$scale]}"
}

# Check for tool availability and install guidance if missing
has(){ command -v "$1" &>/dev/null; }

require_tool(){
  local tool="$1" pkg="${2:-$1}" alt="${3:-}"

  if has "$tool"; then
    return 0
  fi

  if [[ -n $alt ]] && has "$alt"; then
    log "${YLW}Using $alt instead of $tool${RST}"
    return 0
  fi

  log_err "${RED}Required tool not found: $tool${RST}"

  # Package manager detection and installation suggestions
  if has pacman; then
    log "${CYN}To install on Arch: sudo pacman -S $pkg${RST}"
  elif has apt-get; then
    log "${CYN}To install on Debian/Ubuntu: sudo apt-get install $pkg${RST}"
  elif has pkg && [[ -d /data/data/com.termux ]]; then
    log "${CYN}To install on Termux: pkg install $pkg${RST}"
  fi

  if [[ -n $alt ]]; then
    log "${CYN}Alternatively, you can install $alt${RST}"
  fi

  return 1
}

# Tool detection and initialization
check_tools(){
  local missing=0

  # Core tools
  for tool in find xargs basename dirname mkdir file stat mktemp; do
    if ! has "$tool"; then
      log_err "${RED}Missing core tool: $tool${RST}"
      missing=1
    fi
  done

  # Find preferred or fallback tools for each category

  # Image processing
  if has compresscli || has pixelsqueeze || has imgc || has image-optimizer; then
    log "${GRN}✓ Image compression tools available${RST}"
  elif require_tool oxipng optipng || require_tool jpegoptim || require_tool pngquant; then
    log "${GRN}✓ Basic image compression tools available${RST}"
  else
    log "${YLW}⚠ Limited image optimization capabilities${RST}"
    missing=1
  fi

  # Conversion tools
  if ! (require_tool cwebp webp || require_tool convert imagemagick); then
    log "${YLW}⚠ WebP conversion will be limited${RST}"
  fi

  # Deduplication
  if [[ ${MEDIA_OPT_DEDUPE} -eq 1 ]]; then
    if has simagef; then
      log "${GRN}✓ Using simagef for deduplication${RST}"
    elif has fclones; then
      log "${GRN}✓ Using fclones for deduplication${RST}"
    elif has jdupes; then
      log "${GRN}✓ Using jdupes for deduplication${RST}"
    else
      log "${YLW}⚠ No deduplication tool found, this feature will be disabled${RST}"
      MEDIA_OPT_DEDUPE=0
    fi
  fi

  # Video processing
  if [[ ${MEDIA_OPT_PROCESS_VIDEOS:-0} -eq 1 ]]; then
    if has SVT-AV1; then
      log "${GRN}✓ Using SVT-AV1-Essential for AV1 encoding${RST}"
    elif has ffmpeg; then
      log "${GRN}✓ Using ffmpeg for video processing${RST}"
    elif has ffzap; then
      log "${GRN}✓ Using ffzap for video processing${RST}"
    else
      log "${YLW}⚠ No video processing tools found, video optimization will be skipped${RST}"
      MEDIA_OPT_PROCESS_VIDEOS=0
    fi
  fi

  if [[ $missing -eq 1 ]]; then
    log_err "${RED}Some required tools are missing. Basic functionality will work but with limited features.${RST}"
    sleep 2
  fi
}

# Image optimization functions
optimize_jpeg(){
  local input="$1" output="${2:-$1}" quality="${3:-85}"

  if has compresscli; then
    compresscli -i "$input" -o "$output" -q "$quality" -t jpeg
    return $?
  elif has pixelsqueeze; then
    pixelsqueeze compress -i "$input" -o "$output" -q "$quality" --format jpg
    return $?
  elif has imgc; then
    imgc "$input" -o "$output" -q "$quality"
    return $?
  elif has jpegoptim; then
    if [[ $input != "$output" ]]; then
      cp "$input" "$output"
    fi
    jpegoptim --strip-all --max="$quality" --all-progressive -q "$output"
    return $?
  else
    log_err "No JPEG optimization tools available"
    return 1
  fi
}

optimize_png(){
  local input="$1" output="${2:-$1}" lossy="${3:-0}"

  if has compresscli; then
    compresscli -i "$input" -o "$output" -t png
    return $?
  elif has pixelsqueeze; then
    pixelsqueeze compress -i "$input" -o "$output" --format png
    return $?
  elif has imgc; then
    imgc "$input" -o "$output"
    return $?
  elif has oxipng; then
    if [[ $input != "$output" ]]; then
      cp "$input" "$output"
    fi
    if [[ $lossy -eq 1 ]] && has pngquant; then
      pngquant --force --speed=1 --quality=65-80 --strip --output="$output" -- "$input"
    fi
    oxipng -o 3 --strip safe -a -i 0 --force "$output"
    return $?
  elif has optipng; then
    if [[ $input != "$output" ]]; then
      cp "$input" "$output"
    fi
    if [[ $lossy -eq 1 ]] && has pngquant; then
      pngquant --force --speed=1 --quality=65-80 --strip --output="$output" -- "$input"
    fi
    optipng -quiet -strip all -o5 "$output"
    return $?
  else
    log_err "No PNG optimization tools available"
    return 1
  fi
}

convert_to_webp(){
  local input="$1" output="$2" quality="${3:-$MEDIA_OPT_WEBP_QUALITY}"

  if has compresscli; then
    compresscli -i "$input" -o "$output" -q "$quality" -t webp
    return $?
  elif has cwebp; then
    cwebp -quiet -q "$quality" -metadata none "$input" -o "$output"
    return $?
  elif has convert; then
    convert "$input" -quality "$quality" "$output"
    return $?
  else
    log_err "No WebP conversion tools available"
    return 1
  fi
}

optimize_video_to_av1(){
  local input="$1" output="$2" preset="${3:-$MEDIA_OPT_AV1_PRESET}" crf="${4:-$MEDIA_OPT_AV1_CRF}"

  if has SVT-AV1; then
    # Using SVT-AV1-Essential
    ffmpeg -i "$input" -c:v libsvtav1 -preset "$preset" -crf "$crf" -c:a libopus -b:a 128k "$output"
    return $?
  elif has ffzap; then
    # Using ffzap wrapper
    ffzap --av1 --preset "$preset" --crf "$crf" "$input" "$output"
    return $?
  elif has ffmpeg; then
    # Fallback to standard ffmpeg
    ffmpeg -i "$input" -c:v libsvtav1 -preset "$preset" -crf "$crf" -c:a libopus -b:a 128k "$output"
    return $?
  else
    log_err "No AV1 encoding tools available"
    return 1
  fi
}

deduplicate_images(){
  local dir="$1"

  if [[ ${MEDIA_OPT_DEDUPE} -ne 1 ]]; then
    return 0
  fi

  log "Checking for duplicate images in $dir..."

  if has simagef; then
    simagef -i "$dir" --similarity 99 --action report | tee -a "$LOG_FILE"
    if [[ ${MEDIA_OPT_DEDUPE_REMOVE:-0} -eq 1 ]]; then
      log "Removing duplicate images..."
      simagef -i "$dir" --similarity 99 --action remove
    fi
    return 0
  elif has fclones; then
    fclones group -p "$dir" -s 99 | tee -a "$LOG_FILE"
    return 0
  elif has jdupes; then
    jdupes -r "$dir" | tee -a "$LOG_FILE"
    return 0
  else
    log "${YLW}Skipping deduplication - no suitable tools found${RST}"
    return 1
  fi
}

# Batch processing functions
process_image(){
  local file="$1"
  local ext="${file##*.}"
  ext="${ext,,}" # Convert to lowercase

  # Create backup if enabled
  if [[ ${MEDIA_OPT_BACKUP} -eq 1 ]]; then
    local backup_dir
    backup_dir="${BACKUP_DIR}/${"${file#./}"%/*}"
    mkdir -p "$backup_dir"
    cp -a "$file" "$backup_dir/"
  fi

  local original_size webp_output
  original_size=$(file_size "$file")
  webp_output="${file%.*}.webp"

  # Skip already optimized WebP files
  if [[ $ext == "webp" ]]; then
    log_debug "Skipping already WebP file: $file"
    return 0
  fi

  log "Processing: $file"

  local tmpfile result=1
  tmpfile=$(mktemp --suffix=".$ext")

  # First try to optimize in original format
  case "$ext" in
  jpg | jpeg)
    optimize_jpeg "$file" "$tmpfile" "$MEDIA_OPT_WEBP_QUALITY"
    result=$?
    ;;
  png)
    optimize_png "$file" "$tmpfile" "$([[ $MEDIA_OPT_QUALITY == *"lossy"* ]] && echo 1 || echo 0)"
    result=$?
    ;;
  gif | svg | webp)
    # Just copy for now, we'll handle conversion to WebP next
    cp "$file" "$tmpfile"
    result=0
    ;;
  *)
    log_err "Unsupported format: $ext"
    rm -f "$tmpfile"
    return 1
    ;;
  esac

  if [[ $result -ne 0 ]]; then
    log_err "Failed to optimize in original format: $file"
    rm -f "$tmpfile"
    return 1
  fi

  # Now try WebP conversion
  local tmp_webp
  tmp_webp=$(mktemp --suffix=".webp")

  if convert_to_webp "$tmpfile" "$tmp_webp"; then
    # Check if WebP is actually smaller
    local optimized_size webp_size
    optimized_size=$(file_size "$tmpfile")
    webp_size=$(file_size "$tmp_webp")

    if [[ $webp_size -gt 0 && $webp_size -lt $optimized_size ]]; then
      # WebP is smaller, use it
      mv "$tmp_webp" "$webp_output"
      rm -f "$tmpfile"

      log "${GRN}Converted to WebP: $file${RST} ($(human_size "$original_size") → $(human_size "$webp_size"), saved $(human_size "$((original_size - webp_size))"))"

      # If user wants to replace original
      if [[ ${MEDIA_OPT_REPLACE:-0} -eq 1 ]]; then
        rm -f "$file"
      fi
    else
      # Original format optimization was better, keep it
      mv "$tmpfile" "$file"
      rm -f "$tmp_webp"

      log "${GRN}Optimized: $file${RST} ($(human_size "$original_size") → $(human_size "$optimized_size"), saved $(human_size "$((original_size - optimized_size))"))"
    fi
  else
    # WebP conversion failed, use optimized original
    mv "$tmpfile" "$file"
    rm -f "$tmp_webp"

    local optimized_size
    optimized_size=$(file_size "$file")

    log "${YLW}Optimized (WebP conversion failed): $file${RST} ($(human_size "$original_size") → $(human_size "$optimized_size"), saved $(human_size "$((original_size - optimized_size))"))"
  fi

  return 0
}

process_video(){
  local file="$1"
  local ext="${file##*.}"
  ext="${ext,,}" # Convert to lowercase

  # Only process videos if enabled
  if [[ ${MEDIA_OPT_PROCESS_VIDEOS:-0} -ne 1 ]]; then
    return 0
  fi

  # Skip already AV1 encoded files
  if ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file" | grep -q "av1"; then
    log_debug "Skipping already AV1-encoded file: $file"
    return 0
  fi

  # Create backup if enabled
  if [[ ${MEDIA_OPT_BACKUP} -eq 1 ]]; then
    local backup_dir
    backup_dir="${BACKUP_DIR}/${"${file#./}"%/*}"
    mkdir -p "$backup_dir"
    cp -a "$file" "$backup_dir/"
  fi

  local original_size
  original_size=$(file_size "$file")

  local output="${file%.*}.av1.mp4"
  log "Processing video: $file → $output"

  if optimize_video_to_av1 "$file" "$output"; then
    local new_size
    new_size=$(file_size "$output")

    log "${GRN}Converted to AV1: $file${RST} ($(human_size "$original_size") → $(human_size "$new_size"), saved $(human_size "$((original_size - new_size))"))"

    # If user wants to replace original
    if [[ ${MEDIA_OPT_REPLACE:-0} -eq 1 ]]; then
      rm -f "$file"
    fi

    return 0
  else
    log_err "Failed to convert video to AV1: $file"
    return 1
  fi
}

# Main processing function
process_directory(){
  local dir="$1"

  # Create backup directory if needed
  if [[ ${MEDIA_OPT_BACKUP} -eq 1 && -z $BACKUP_DIR ]]; then
    BACKUP_DIR="${dir%/}_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    log "Backups will be saved in ${CYN}$BACKUP_DIR${RST}"
  fi

  # Find all supported image files
  log "Finding media files in $dir..."

  local find_cmd=()
  if has fd; then
    # Optimized finder with fd
    find_cmd=(fd -t f -e jpg -e jpeg -e png -e gif -e webp -e svg .)
    [[ ${MEDIA_OPT_RECURSIVE} -eq 0 ]] && find_cmd+=(--max-depth 1)
  else
    # Standard find fallback
    find_cmd=(find "$dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" -o -iname "*.svg" \))
    [[ ${MEDIA_OPT_RECURSIVE} -eq 0 ]] && find_cmd+=(-maxdepth 1)
  fi

  # Process images in parallel
  local image_files=()
  if has fd; then
    # Using fd in the directory
    pushd "$dir" >/dev/null || return 1
    mapfile -t image_files < <("${find_cmd[@]}")
    popd >/dev/null || return 1

    # Prepend the directory
    for i in "${!image_files[@]}"; do
      image_files[$i]="$dir/${image_files[$i]}"
    done
  else
    # Using standard find
    mapfile -t image_files < <("${find_cmd[@]}")
  fi

  log "Found ${#image_files[@]} image files"

  if [[ ${#image_files[@]} -gt 0 ]]; then
    # Process using xargs for parallelization
    printf '%s\0' "${image_files[@]}" | xargs -0 -P "$MEDIA_OPT_THREADS" -I{} bash -c '
      source "$0"
      process_image "{}"
    ' "$0"

    # Run deduplication if enabled
    deduplicate_images "$dir"
  fi

  # Process videos if enabled
  if [[ ${MEDIA_OPT_PROCESS_VIDEOS:-0} -eq 1 ]]; then
    local video_find_cmd=()

    if has fd; then
      video_find_cmd=(fd -t f -e mp4 -e avi -e mkv -e mov -e webm .)
      [[ ${MEDIA_OPT_RECURSIVE} -eq 0 ]] && video_find_cmd+=(--max-depth 1)
    else
      video_find_cmd=(find "$dir" -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \))
      [[ ${MEDIA_OPT_RECURSIVE} -eq 0 ]] && video_find_cmd+=(-maxdepth 1)
    fi

    local video_files=()
    if has fd; then
      pushd "$dir" >/dev/null || return 1
      mapfile -t video_files < <("${video_find_cmd[@]}")
      popd >/dev/null || return 1

      for i in "${!video_files[@]}"; do
        video_files[$i]="$dir/${video_files[$i]}"
      done
    else
      mapfile -t video_files < <("${video_find_cmd[@]}")
    fi

    log "Found ${#video_files[@]} video files"

    if [[ ${#video_files[@]} -gt 0 ]]; then
      # Process videos one by one as they're CPU intensive
      for video in "${video_files[@]}"; do
        process_video "$video"
      done
    fi
  fi
}

# Command-line interface
usage(){
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] DIRECTORY

Media optimization toolkit for images and videos.

Options:
  -h, --help              Show this help
  -q, --quality LEVEL     Quality level: auto|lossless|lossy-low|lossy-medium|lossy-high
                          (default: auto - selected based on file characteristics)
  -j, --jobs NUM          Number of parallel jobs (default: $(nproc))
  -r, --recursive         Process directories recursively
  -b, --backup            Create backups of original files
  -n, --no-backup         Don't create backups
  -p, --replace           Replace original files with optimized versions
  -w, --webp-quality NUM  WebP quality (0-100, default: 80)
  -v, --video             Process videos (convert to AV1)
  -d, --dedupe            Enable deduplication (find similar images)
  --debug                 Enable debug output

Examples:
  $SCRIPT_NAME ~/Pictures
  $SCRIPT_NAME -j 4 -q lossy-medium -r -b ~/Media
  $SCRIPT_NAME -v -w 85 ~/Videos
EOF
  exit 1
}

# Main function
main(){
  local target_dir=""

  # Parse command-line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      usage
      ;;
    -q | --quality)
      MEDIA_OPT_QUALITY="$2"
      shift 2
      ;;
    -j | --jobs)
      MEDIA_OPT_THREADS="$2"
      shift 2
      ;;
    -r | --recursive)
      MEDIA_OPT_RECURSIVE=1
      shift
      ;;
    -b | --backup)
      MEDIA_OPT_BACKUP=1
      shift
      ;;
    -n | --no-backup)
      MEDIA_OPT_BACKUP=0
      shift
      ;;
    -p | --replace)
      MEDIA_OPT_REPLACE=1
      shift
      ;;
    -w | --webp-quality)
      MEDIA_OPT_WEBP_QUALITY="$2"
      shift 2
      ;;
    -v | --video)
      MEDIA_OPT_PROCESS_VIDEOS=1
      shift
      ;;
    -d | --dedupe)
      MEDIA_OPT_DEDUPE=1
      shift
      ;;
    --debug)
      MEDIA_OPT_DEBUG=1
      shift
      ;;
    -*)
      log_err "Unknown option: $1"
      usage
      ;;
    *)
      if [[ -z $target_dir ]]; then
        target_dir="$1"
      else
        log_err "Multiple directories specified. Please specify only one directory."
        usage
      fi
      shift
      ;;
    esac
  done

  # Check if target directory was provided
  if [[ -z $target_dir ]]; then
    log_err "No directory specified"
    usage
  fi

  # Validate directory
  if [[ ! -d $target_dir ]]; then
    log_err "Not a directory: $target_dir"
    exit 1
  fi

  # Convert to absolute path
  target_dir=$(cd "$target_dir" && pwd)

  # Check for required tools
  check_tools

  # Show settings
  log "Media Optimizer v1.0"
  log "Target directory: ${CYN}$target_dir${RST}"
  log "Mode: $((MEDIA_OPT_RECURSIVE)) ? recursive : non-recursive"
  log "Quality: ${CYN}$MEDIA_OPT_QUALITY${RST}"
  log "Threads: ${CYN}$MEDIA_OPT_THREADS${RST}"
  [[ ${MEDIA_OPT_BACKUP} -eq 1 ]] && log "Backup: ${GRN}enabled${RST}" || log "Backup: ${YLW}disabled${RST}"
  [[ ${MEDIA_OPT_PROCESS_VIDEOS:-0} -eq 1 ]] && log "Video processing: ${GRN}enabled${RST}" || log "Video processing: ${YLW}disabled${RST}"
  [[ ${MEDIA_OPT_DEDUPE} -eq 1 ]] && log "Deduplication: ${GRN}enabled${RST}" || log "Deduplication: ${YLW}disabled${RST}"

  # Process the directory
  process_directory "$target_dir"

  log "${GRN}All operations completed successfully!${RST}"
}

# Run the main function with all arguments
main "$@"
