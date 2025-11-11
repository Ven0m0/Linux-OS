#!/usr/bin/env bash
# Unified media optimizer for Arch Linux desktop & Termux Android
# Features: lossless/lossy, parallel, auto codec detection, TUI mode, dry-run
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'; export LC_ALL=C LANG=C

# ---- Environment Detection ----
if [[ -n ${TERMUX_VERSION:-} || -d /data/data/com.termux ]]; then
  ENV="termux"
  HOME="${HOME:-/data/data/com.termux/files/home}"
else
  ENV="desktop"
fi

# ---- Colors ----
if [[ -t 1 ]]; then
  R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' X=$'\e[0m'
else
  R= G= Y= B= X=
fi

# ---- Tool Cache & Wrappers ----
declare -A T=()
cache_tool(){
  local tool=$1 alt=${2:-}
  [[ -n ${T[$tool]:-} ]] && return 0
  T[$tool]=$(command -v "$tool" 2>/dev/null || command -v "$alt" 2>/dev/null || echo "")
  [[ -n ${T[$tool]} ]]
}
has(){ cache_tool "$1"; }

# Pre-cache critical tools
for tool in fd:fdfind rg:grep sk:fzf eza:ls rust-parallel:parallel ffzap:ffmpeg; do
  IFS=: read -r name fallback <<<"$tool"
  cache_tool "$name" "$fallback" || :
done

# ---- Tool Execution Wrappers ----
run_fd(){ [[ -n ${T[fd]:-} ]] && "${T[fd]}" "$@" || find "$@"; }
run_rg(){ [[ -n ${T[rg]:-} ]] && "${T[rg]}" "$@" || grep -E "$@"; }
run_parallel(){ 
  if [[ -n ${T[rust-parallel]:-} ]]; then
    "${T[rust-parallel]}" "$@"
  elif [[ -n ${T[parallel]:-} ]]; then
    "${T[parallel]}" "$@"
  else
    xargs -r -P"$(nproc)" "$@"
  fi
}

# ---- Helpers ----
log(){ printf '%s\n' "$*"; }
warn(){ printf '%s%s%s\n' "$Y" "$*" "$X" >&2; }
err(){ printf '%s%s%s\n' "$R" "ERROR: $*" "$X" >&2; exit "${2:-1}"; }

get_size(){
  local f=$1
  [[ -f $f ]] && { stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0; } || echo 0
}

format_bytes(){
  local bytes=$1
  ((bytes<1024)) && { echo "${bytes}B"; return; }
  ((bytes<1048576)) && { echo "$((bytes/1024))K"; return; }
  ((bytes<1073741824)) && { echo "$((bytes/1048576))M"; return; }
  echo "$((bytes/1073741824))G"
}

abs_path(){
  local path=$1
  [[ $path == /* ]] && echo "$path" || echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
}

# ---- Config / Defaults ----
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
QUALITY=85 VIDEO_CRF=27 VIDEO_CODEC="auto" AUDIO_BITRATE=128 JOBS=0 SUFFIX="_opt"
KEEP_ORIGINAL=0 INPLACE=0 RECURSIVE=0 CONVERT_FORMAT="" LOSSLESS=1 OUTPUT_DIR=""
MEDIA_TYPE="all" DRY_RUN=0 SKIP_EXISTING=0 PROGRESS=0 MIN_SAVINGS=0 TUI_MODE=0 KEEP_BACKUPS=1
WEBP_QUALITY=80 AVIF_SPEED=6 AVIF_QUAL=40
IMAGE_CODEC_PRIORITY=("webp" "avif" "jxl" "jpg" "png")

declare -g STATS_TOTAL=0 STATS_PROCESSED=0 STATS_SKIPPED=0 STATS_FAILED=0
declare -g STATS_BYTES_BEFORE=0 STATS_BYTES_AFTER=0

# ---- Temp Management ----
TEMP_DIR=$(mktemp -d -t "optimize.XXXXXX" 2>/dev/null || mktemp -d)
cleanup(){
  [[ -n $TEMP_DIR && -d $TEMP_DIR ]] && rm -rf "$TEMP_DIR" 2>/dev/null || :
  find /tmp -maxdepth 1 -name "optimize.*.tmp" -user "$(id -u)" -mmin +60 -delete 2>/dev/null || :
}
trap cleanup EXIT INT TERM

# ---- Codec Detection ----
FFMPEG_ENCODERS=""
ffmpeg_has_encoder(){
  cache_tool ffmpeg || cache_tool ffzap || return 1
  if [[ -z $FFMPEG_ENCODERS ]]; then
    if [[ -n ${T[ffmpeg]:-} ]]; then
      FFMPEG_ENCODERS=$("${T[ffmpeg]}" -hide_banner -encoders 2>/dev/null || :)
    else
      FFMPEG_ENCODERS="libsvtav1 libaom-av1 libvpx-vp9 libx265 libx264 libopus"
    fi
  fi
  [[ $FFMPEG_ENCODERS == *"$1"* ]]
}

detect_video_codec(){
  local req=${VIDEO_CODEC,,}
  [[ -n $req && $req != "auto" ]] && { VIDEO_CODEC=$req; return; }
  if ffmpeg_has_encoder libsvtav1 || ffmpeg_has_encoder libaom-av1; then VIDEO_CODEC="av1"
  elif ffmpeg_has_encoder libvpx-vp9; then VIDEO_CODEC="vp9"
  elif ffmpeg_has_encoder libx265; then VIDEO_CODEC="h265"
  elif ffmpeg_has_encoder libx264; then VIDEO_CODEC="h264"
  else VIDEO_CODEC="vp9"; fi
}

# ---- Backup ----
mkbackup(){
  [[ $KEEP_BACKUPS -eq 0 ]] && return 0
  local file=$1 bakdir="$(dirname "$file")/.backups"
  mkdir -p "$bakdir" 2>/dev/null || return 1
  cp -p "$file" "$bakdir/" 2>/dev/null || warn "Backup failed: $(basename "$file")"
}

# ---- Output Path ----
get_output_path(){
  local src=$1 fmt=$2 base="${src##*/}" name="${base%.*}" ext="${base##*.}"
  local dir="${OUTPUT_DIR:-${src%/*}}"
  if [[ -n $fmt && $fmt != "${ext,,}" ]]; then echo "$dir/${name}.${fmt}"
  elif [[ $INPLACE -eq 1 ]]; then echo "$dir/$base"
  else echo "$dir/${name}${SUFFIX}.${ext}"; fi
}

# ---- Already Optimized Check ----
is_already_optimized(){
  local file=$1 ext="${file##*.}" && ext="${ext,,}"
  [[ $file == *"$SUFFIX"* ]] && return 0
  case "$ext" in
    webp|avif|jxl) return 0;;
    jpg|jpeg)
      if cache_tool identify; then
        local q=$(identify -format '%Q' "$file" 2>/dev/null || echo 100)
        ((q<90)) && return 0
      fi;;
  esac
  return 1
}

# ---- Progress ----
show_progress(){
  [[ $PROGRESS -eq 0 ]] && return
  local cur=$1 tot=$2 msg=${3:-}
  local pct=$((cur*100/tot)) bar_len=40 filled=$((pct*bar_len/100)) empty=$((bar_len-filled))
  printf '\r[%*s%*s] %3d%% (%d/%d) %s' "$filled" '' "$empty" '' "$pct" "$cur" "$tot" "$msg" | tr ' ' '='
}

print_stats(){
  log "" "=== Statistics ==="
  log "Total: $STATS_TOTAL | Processed: $STATS_PROCESSED | Skipped: $STATS_SKIPPED | Failed: $STATS_FAILED"
  if ((STATS_PROCESSED>0 && STATS_BYTES_BEFORE>0)); then
    local saved=$((STATS_BYTES_BEFORE-STATS_BYTES_AFTER))
    ((saved>0)) && log "Original: $(format_bytes "$STATS_BYTES_BEFORE") → Final: $(format_bytes "$STATS_BYTES_AFTER") | Saved: $(format_bytes "$saved") ($((saved*100/STATS_BYTES_BEFORE))%)"
  fi
}

# ---- Image Optimization ----
optimize_png(){
  local src=$1 out=$2 tmp="${TEMP_DIR}/$(basename "$out").tmp" orig=$(get_size "$src") success=0
  cp "$src" "$tmp"
  if cache_tool oxipng; then
    oxipng -o6 --strip safe -q "$tmp" &>/dev/null && success=1
    [[ $LOSSLESS -eq 0 ]] && cache_tool pngquant && pngquant --quality=65-"$QUALITY" --strip --speed 1 -f "$tmp" -o "${tmp}.2" &>/dev/null && mv "${tmp}.2" "$tmp" || :
  elif cache_tool optipng; then
    optipng -o7 -strip all -quiet "$tmp" &>/dev/null && success=1
    [[ $LOSSLESS -eq 0 ]] && cache_tool pngquant && pngquant --quality=65-"$QUALITY" --strip --speed 1 -f "$src" -o "$tmp" &>/dev/null || :
  fi
  cache_tool flaca && flaca --no-symlinks --preserve-times "$tmp" &>/dev/null || :
  [[ $success -eq 1 ]] && mv "$tmp" "$out" && echo "$((orig-$(get_size "$out")))" || { rm -f "$tmp"; return 1; }
}

optimize_jpeg(){
  local src=$1 out=$2 tmp="${TEMP_DIR}/$(basename "$out").tmp" orig=$(get_size "$src") success=0
  if cache_tool jpegoptim; then
    [[ $LOSSLESS -eq 1 ]] && jpegoptim --strip-all --all-progressive --stdout "$src" >"$tmp" 2>/dev/null && success=1
    [[ $LOSSLESS -eq 0 ]] && jpegoptim --max="$QUALITY" --strip-all --all-progressive --stdout "$src" >"$tmp" 2>/dev/null && success=1
  elif cache_tool cjpeg; then
    cjpeg -quality "$QUALITY" -optimize "$src" >"$tmp" 2>/dev/null && success=1
  fi
  cache_tool flaca && flaca --no-symlinks --preserve-times "$tmp" &>/dev/null || :
  cache_tool rimage && rimage -i "$tmp" -o "${tmp}.r" &>/dev/null && mv -f "${tmp}.r" "$tmp" || :
  [[ $success -eq 1 ]] && mv "$tmp" "$out" && echo "$((orig-$(get_size "$out")))" || { rm -f "$tmp"; return 1; }
}

select_image_target_format(){
  local ext=${1,,}
  [[ -n $CONVERT_FORMAT ]] && { echo "$CONVERT_FORMAT"; return; }
  ((LOSSLESS==1)) && { echo "$ext"; return; }
  for c in "${IMAGE_CODEC_PRIORITY[@]}"; do
    case "$c" in
      webp) cache_tool cwebp && { echo "webp"; return; };;
      avif) cache_tool avifenc && { echo "avif"; return; };;
      jxl) cache_tool cjxl && { echo "jxl"; return; };;
      jpg|png) { echo "$c"; return; };;
    esac
  done
  echo "$ext"
}

optimize_image(){
  local src=$1 ext="${src##*.}" && ext="${ext,,}" out fmt
  [[ $SKIP_EXISTING -eq 1 ]] && is_already_optimized "$src" && { ((STATS_SKIPPED++)); return 0; }
  fmt=$(select_image_target_format "$ext")
  out=$(get_output_path "$src" "$fmt")
  [[ -f $out && $KEEP_ORIGINAL -eq 1 && $INPLACE -eq 0 ]] && { ((STATS_SKIPPED++)); return 0; }
  local orig=$(get_size "$src") new saved pct
  ((STATS_BYTES_BEFORE+=orig))
  [[ $DRY_RUN -eq 1 ]] && { log "[DRY] Would process: $(basename "$src") → $fmt"; return 0; }
  log "Processing: $(basename "$src")"
  # Format conversion
  if [[ $fmt != "$ext" ]]; then
    local tmp="${out}.tmp" success=0
    case "$fmt" in
      webp) cache_tool cwebp && cwebp -q "$QUALITY" -m 6 -mt -af "$src" -o "$tmp" &>/dev/null && success=1;;
      avif) cache_tool avifenc && avifenc -s "$AVIF_SPEED" -j "$NPROC" --min 0 --max "$AVIF_QUAL" "$src" "$tmp" &>/dev/null && success=1;;
      jxl)
        if cache_tool cjxl; then
          [[ $LOSSLESS -eq 1 ]] && cjxl "$src" "$tmp" -d 0 -e 7 &>/dev/null && success=1
          [[ $LOSSLESS -eq 0 ]] && cjxl "$src" "$tmp" -q "$QUALITY" -e 7 &>/dev/null && success=1
        fi;;
    esac
    [[ $success -eq 1 ]] && mv "$tmp" "$out" || { warn "Conversion to $fmt failed"; rm -f "$tmp"; return 1; }
  else
    case "$ext" in
      png) optimize_png "$src" "$out" >/dev/null || return 1;;
      jpg|jpeg) optimize_jpeg "$src" "$out" >/dev/null || return 1;;
      gif) cache_tool gifsicle && gifsicle -O3 "$src" -o "$out" &>/dev/null || cp "$src" "$out";;
      svg) cache_tool svgo && svgo -i "$src" -o "$out" &>/dev/null || cache_tool scour && scour -i "$src" -o "$out" --enable-id-stripping &>/dev/null || cp "$src" "$out";;
      webp) cache_tool cwebp && cwebp -q "$QUALITY" -m 6 -mt "$src" -o "$out" &>/dev/null || cp "$src" "$out";;
      avif) cache_tool avifenc && avifenc -s "$AVIF_SPEED" -j "$NPROC" --min 0 --max "$AVIF_QUAL" "$src" "$out" &>/dev/null || cp "$src" "$out";;
      jxl) cache_tool cjxl && cjxl "$src" "$out" -d 0 -e 7 &>/dev/null || cp "$src" "$out";;
      *) warn "Unsupported: $ext"; return 1;;
    esac
  fi
  new=$(get_size "$out")
  if ((new>0 && new<orig)); then
    saved=$((orig-new)) pct=$((saved*100/orig))
    ((MIN_SAVINGS>0 && pct<MIN_SAVINGS)) && { warn "Savings ${pct}% < threshold ${MIN_SAVINGS}%"; rm -f "$out"; ((STATS_SKIPPED++)); return 1; }
    ((STATS_BYTES_AFTER+=new)) && ((STATS_PROCESSED++))
    printf '%s → %s | %s → %s (%d%%)\n' "$(basename "$src")" "$(basename "$out")" "$(format_bytes "$orig")" "$(format_bytes "$new")" "$pct"
    [[ $INPLACE -eq 1 || $KEEP_ORIGINAL -eq 0 ]] && mkbackup "$src" && [[ $src != "$out" ]] && rm -f "$src"
  elif ((new>=orig)); then
    [[ $fmt == "$ext" ]] && { warn "No savings: $(basename "$src")"; rm -f "$out"; ((STATS_FAILED++)); return 1; }
    ((STATS_BYTES_AFTER+=new)) && ((STATS_PROCESSED++))
  fi
}

# ---- Video Optimization ----
optimize_video(){
  local src=$1 ext="${src##*.}" out=$(get_output_path "$src" "$ext")
  [[ -f $out && $KEEP_ORIGINAL -eq 1 && $INPLACE -eq 0 ]] && return 0
  local orig=$(get_size "$src")
  log "Processing video: $(basename "$src")"
  local -a enc=() ac=(-c:a libopus -b:a "${AUDIO_BITRATE}k")
  case "$VIDEO_CODEC" in
    av1) ffmpeg_has_encoder libsvtav1 && enc=(-c:v libsvtav1 -preset 8 -crf "$VIDEO_CRF" -g 240) || enc=(-c:v libaom-av1 -cpu-used 6 -crf "$VIDEO_CRF" -g 240);;
    vp9) enc=(-c:v libvpx-vp9 -crf "$VIDEO_CRF" -b:v 0 -row-mt 1);;
    h265|hevc) enc=(-c:v libx265 -preset medium -crf "$VIDEO_CRF" -tag:v hvc1);;
    h264) enc=(-c:v libx264 -preset medium -crf "$VIDEO_CRF");;
    *) enc=(-c:v libvpx-vp9 -crf "$VIDEO_CRF" -b:v 0 -row-mt 1);;
  esac
  local success=0 tool=""
  if cache_tool ffzap; then
    tool="ffzap"
    "${T[ffzap]}" -i "$src" -f "${enc[*]} ${ac[*]}" -o "$out" -t 1 &>/dev/null && success=1
  elif cache_tool ffmpeg; then
    tool="ffmpeg"
    "${T[ffmpeg]}" -i "$src" "${enc[@]}" "${ac[@]}" -y "$out" -loglevel error && success=1
  else
    warn "No video encoder found (ffzap/ffmpeg required)"; return 1
  fi
  [[ $success -eq 0 ]] && { warn "Video optimization failed"; return 1; }
  local new=$(get_size "$out")
  ((new>0 && new<orig)) && {
    local saved=$((orig-new)) pct=$((saved*100/orig))
    printf '%s → %s | %s → %s (%d%%) [%s/%s]\n' "$(basename "$src")" "$(basename "$out")" "$(format_bytes "$orig")" "$(format_bytes "$new")" "$pct" "$tool" "$VIDEO_CODEC"
    [[ $INPLACE -eq 1 || $KEEP_ORIGINAL -eq 0 ]] && mkbackup "$src" && [[ $src != "$out" ]] && rm -f "$src"
  } || { warn "No savings"; rm -f "$out"; return 1; }
}

# ---- Audio Optimization ----
optimize_audio(){
  local src=$1 ext="${src##*.}" && ext="${ext,,}" out
  if [[ $ext == "opus" ]]; then
    out=$(get_output_path "$src" "$ext")
    [[ -f $out && $KEEP_ORIGINAL -eq 1 && $INPLACE -eq 0 ]] && return 0
    local orig=$(get_size "$src")
    log "Processing audio: $(basename "$src")"
    if cache_tool opusenc; then
      local tmp="${out}.tmp"
      opusenc --bitrate "$AUDIO_BITRATE" --vbr "$src" "$tmp" &>/dev/null || return 1
      [[ -f $tmp ]] && mv "$tmp" "$out" || return 1
    else cp "$src" "$out"; fi
  else
    out="${src%.*}.opus"
    [[ -n $CONVERT_FORMAT ]] && out=$(get_output_path "$src" "$CONVERT_FORMAT") || out=$(get_output_path "$src" "opus")
    [[ -f $out && $KEEP_ORIGINAL -eq 1 && $INPLACE -eq 0 ]] && return 0
    local orig=$(get_size "$src")
    log "Processing audio: $(basename "$src") → Opus"
    if cache_tool opusenc && [[ $ext == "wav" || $ext == "flac" ]]; then
      opusenc --bitrate "$AUDIO_BITRATE" --vbr "$src" "$out" &>/dev/null || return 1
    elif cache_tool ffmpeg || cache_tool ffzap; then
      local tool=${T[ffzap]:-${T[ffmpeg]}}
      if [[ $(basename "$tool") == "ffzap" ]]; then
        "$tool" -i "$src" -f "-c:a libopus -b:a ${AUDIO_BITRATE}k" -o "$out" -t 1 &>/dev/null || return 1
      else
        "$tool" -i "$src" -c:a libopus -b:a "${AUDIO_BITRATE}k" -vbr on -y "$out" -loglevel error || return 1
      fi
    else
      warn "No audio encoder found (opusenc/ffzap/ffmpeg required)"; return 1
    fi
  fi
  local new=$(get_size "$out")
  ((new<orig)) && {
    local saved=$((orig-new)) pct=$((saved*100/orig))
    printf '%s → %s | %s → %s (%d%%)\n' "$(basename "$src")" "$(basename "$out")" "$(format_bytes "$orig")" "$(format_bytes "$new")" "$pct"
    [[ $INPLACE -eq 1 || $KEEP_ORIGINAL -eq 0 ]] && mkbackup "$src" && [[ $src != "$out" ]] && rm -f "$src"
  }
}

# ---- Process File ----
process_file(){
  local file=$1 ext="${file##*.}" && ext="${ext,,}"
  ((STATS_TOTAL++))
  [[ $INPLACE -eq 0 && $file == *"$SUFFIX"* ]] && { ((STATS_SKIPPED++)); return 0; }
  show_progress "$STATS_TOTAL" "${TOTAL_FILES:-$STATS_TOTAL}" "$(basename "$file")"
  case "$ext" in
    jpg|jpeg|png|gif|svg|webp|avif|jxl|tiff|tif|bmp)
      [[ $MEDIA_TYPE == "all" || $MEDIA_TYPE == "image" ]] && optimize_image "$file" || :;;
    mp4|mkv|mov|webm|avi|flv)
      [[ $MEDIA_TYPE == "all" || $MEDIA_TYPE == "video" ]] && optimize_video "$file" || :;;
    opus|flac|mp3|m4a|aac|ogg|wav)
      [[ $MEDIA_TYPE == "all" || $MEDIA_TYPE == "audio" ]] && optimize_audio "$file" || :;;
    *) warn "Unsupported: $file"; ((STATS_SKIPPED++));;
  esac
}
export -f process_file optimize_image optimize_video optimize_audio optimize_png optimize_jpeg
export -f get_size format_bytes get_output_path is_already_optimized mkbackup cache_tool select_image_target_format ffmpeg_has_encoder

# ---- File Collection ----
collect_files(){
  local -a files=() items=("$@")
  if [[ ${#items[@]} -eq 0 ]]; then
    while IFS= read -r f; do [[ -f $f ]] && files+=("$(abs_path "$f")"); done
  else
    local exts=(jpg jpeg png gif svg webp avif jxl tiff tif bmp mp4 mkv mov webm avi flv opus flac mp3 m4a aac ogg wav)
    for item in "${items[@]}"; do
      if [[ -f $item ]]; then files+=("$(abs_path "$item")")
      elif [[ -d $item ]]; then
        local -a found=()
        if cache_tool fd; then
          local -a args=(-t f)
          for e in "${exts[@]}"; do args+=(-e "$e"); done
          [[ $RECURSIVE -eq 0 ]] && args+=(-d 1)
          mapfile -t -d '' found < <("${T[fd]}" "${args[@]}" . "$(abs_path "$item")" -0 2>/dev/null || :)
        else
          local -a fargs=(-type f)
          [[ $RECURSIVE -eq 0 ]] && fargs+=(-maxdepth 1)
          local -a pats=()
          for e in "${exts[@]}"; do pats+=(-o -iname "*.$e"); done
          pats=("${pats[@]:1}")
          mapfile -t found < <(find "$(abs_path "$item")" "${fargs[@]}" \( "${pats[@]}" \) 2>/dev/null || :)
        fi
        files+=("${found[@]}")
      fi
    done
  fi
  printf '%s\n' "${files[@]}"
}

# ---- TUI Mode ----
tui_select(){
  local dir=$1
  cache_tool sk || cache_tool fzf || err "TUI requires sk or fzf"
  local picker=${T[sk]:-${T[fzf]}}
  local -a selected=()
  mapfile -t selected < <(collect_files "$dir" | "$picker" --multi --height=80% --layout=reverse --prompt="Select files > " | tr '\0' '\n')
  [[ ${#selected[@]} -eq 0 ]] && { log "No selection"; exit 0; }
  printf '%s\n' "${selected[@]}"
}

# ---- Parallel Dispatch ----
dispatch_parallel(){
  local -a files=("${@}")
  [[ ${#files[@]} -eq 0 ]] && return 0
  if cache_tool rust-parallel; then
    printf '%s\0' "${files[@]}" | "${T[rust-parallel]}" -0 -j "$JOBS" bash -c 'process_file "$@"' _ {}
  elif cache_tool parallel; then
    printf '%s\0' "${files[@]}" | "${T[parallel]}" -0 -j "$JOBS" bash -c 'process_file "$@"' _ {}
  else
    printf '%s\0' "${files[@]}" | xargs -0 -P "$JOBS" -n 1 bash -c 'process_file "$@"' _
  fi
}

# ---- Usage ----
usage(){
  cat <<EOF
optimize - System-independent media optimizer (Arch Linux / Termux)

USAGE: ${0##*/} [OPTIONS] [files/dirs...]
       <stdin> | ${0##*/} [OPTIONS]

OPTIONS:
  -h            Show help
  -t TYPE       Media type: all, image, video, audio (default: all)
  -q N          Quality 1-100 (default: $QUALITY)
  -c N          Video CRF 0-51 (default: $VIDEO_CRF)
  -C CODEC      Video codec: auto, av1, vp9, h265, h264 (default: auto)
  -b N          Audio bitrate kbps (default: $AUDIO_BITRATE) [Opus only]
  -f FMT        Convert format: webp, avif, jxl, png, jpg (images only)
  -o DIR        Output directory (default: same as input)
  -k            Keep originals
  -i            Replace in-place
  -r            Recursive
  -j N          Parallel jobs (default: auto)
  -l            Lossy mode
  -n            Dry-run
  -s            Skip already optimized
  -p            Show progress
  -T            TUI mode (interactive)
  -B            Keep backups (default)
  --no-backup   Disable backups
  --min-save N  Min % savings (default: 0)

NOTES:
  - Audio: Always encodes to Opus (video + standalone audio files)
  - Video: Uses ffzap if available, falls back to ffmpeg
  - Codecs: Auto-detects best available (AV1 > VP9 > H265 > H264)

EXAMPLES:
  ${0##*/} .
  ${0##*/} -T ~/Pictures
  ${0##*/} -f webp -q 90 -r ~/Pictures
  ${0##*/} -t video -C av1 -c 28 -b 96 video.mp4
  find . -name "*.jpg" | ${0##*/} -q 85
EOF
}

# ---- Main ----
main(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0;;
      -t|--type) MEDIA_TYPE="${2,,}"; shift 2;;
      -q|--quality) QUALITY="$2"; shift 2;;
      -c|--crf) VIDEO_CRF="$2"; shift 2;;
      -C|--codec) VIDEO_CODEC="${2,,}"; shift 2;;
      -b|--bitrate) AUDIO_BITRATE="$2"; shift 2;;
      -f|--format) CONVERT_FORMAT="${2,,}"; LOSSLESS=0; shift 2;;
      -o|--output) OUTPUT_DIR="$2"; shift 2;;
      -k|--keep) KEEP_ORIGINAL=1; shift;;
      -i|--inplace) INPLACE=1; KEEP_ORIGINAL=0; shift;;
      -r|--recursive) RECURSIVE=1; shift;;
      -j|--jobs) JOBS="$2"; shift 2;;
      -l|--lossy) LOSSLESS=0; shift;;
      -n|--dry-run) DRY_RUN=1; shift;;
      -s|--skip-existing) SKIP_EXISTING=1; shift;;
      -p|--progress) PROGRESS=1; shift;;
      -T|--tui) TUI_MODE=1; shift;;
      -B) KEEP_BACKUPS=1; shift;;
      --no-backup) KEEP_BACKUPS=0; shift;;
      --min-save) MIN_SAVINGS="$2"; shift 2;;
      -*) err "Unknown: $1 (use -h)";;
      *) break;;
    esac
  done
  ((QUALITY>=1 && QUALITY<=100)) || err "Quality: 1-100"
  ((VIDEO_CRF>=0 && VIDEO_CRF<=51)) || err "CRF: 0-51"
  ((AUDIO_BITRATE>=6 && AUDIO_BITRATE<=510)) || err "Bitrate: 6-510 kbps"
  [[ -n $OUTPUT_DIR ]] && mkdir -p "$OUTPUT_DIR" && OUTPUT_DIR=$(abs_path "$OUTPUT_DIR")
  # TUI Mode
  if [[ $TUI_MODE -eq 1 ]]; then
    local target="${1:-.}"
    mapfile -t FILES < <(tui_select "$target")
  else
    mapfile -t FILES < <(collect_files "$@")
  fi
  [[ ${#FILES[@]} -eq 0 ]] && err "No files found"
  export TOTAL_FILES=${#FILES[@]}
  ((JOBS<=0)) && JOBS=$NPROC
  ((JOBS>TOTAL_FILES)) && JOBS=$TOTAL_FILES
  ((JOBS<1)) && JOBS=1
  [[ $MEDIA_TYPE == "all" || $MEDIA_TYPE == "video" ]] && detect_video_codec
  local enc_tool="ffmpeg"
  cache_tool ffzap && enc_tool="ffzap"
  log "Processing ${#FILES[@]} files (${ENV^^}) | Jobs: $JOBS | Mode: $([[ $LOSSLESS -eq 1 ]] && echo "Lossless" || echo "Lossy Q=$QUALITY")"
  [[ $DRY_RUN -eq 1 ]] && log "DRY RUN - no files modified"
  [[ -n $CONVERT_FORMAT ]] && log "Convert → $CONVERT_FORMAT"
  [[ $MEDIA_TYPE == "all" || $MEDIA_TYPE == "video" ]] && log "Video: ${VIDEO_CODEC^^} via $enc_tool | Audio: Opus @ ${AUDIO_BITRATE}kbps"
  [[ $MEDIA_TYPE == "all" || $MEDIA_TYPE == "audio" ]] && log "Audio: Opus @ ${AUDIO_BITRATE}kbps via $enc_tool"
  if ((JOBS==1)); then
    for f in "${FILES[@]}"; do process_file "$f" || :; done
    [[ $PROGRESS -eq 1 ]] && echo ""
    print_stats
  else
    dispatch_parallel "${FILES[@]}"
    log "Stats unavailable in parallel mode"
  fi
  log "Complete"
}

[[ ${BASH_SOURCE[0]} == "${0}" ]] && main "$@"
