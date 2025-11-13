#!/usr/bin/env bash
# Media optimizer for Arch/Termux - images, video, audio
set -Eeuo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C LANG=C
# -- Colors --
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' X=$'\e[0m'
# -- Tool resolution (cached) --
declare -gA TOOLS=()
has(){
  local t=$1 alt=${2:-}
  [[ -n ${TOOLS[$t]:-} ]] && return 0
  TOOLS[$t]=$(command -v "$t" || command -v "$alt" || echo "") 
  [[ -n ${TOOLS[$t]} ]]
}

# -- Core helpers --
die(){ printf '%sERROR: %s%s\n' "$R" "$1" "$X" >&2; exit "${2:-1}"; }
warn(){ printf '%sWARN: %s%s\n' "$Y" "$1" "$X" >&2; }
log(){ printf '%s\n' "$*"; }

# -- Config --
declare -g QUALITY=85 VIDEO_CRF=27 AUDIO_BITRATE=128
declare -g LOSSLESS=1 RECURSIVE=0 DRY_RUN=0 INPLACE=0 KEEP_ORIG=0
declare -g OUTPUT_DIR="" FORMAT="" MEDIA_TYPE="all" MIN_SAVE=0
declare -g JOBS=$(nproc) SUFFIX="_opt" TUI=0 SKIP_OPT=0
declare -gi TOTAL=0 PROCESSED=0 SKIPPED=0 FAILED=0

# -- File discovery --
find_media(){
  local dir=${1:-.} depth_arg=""
  [[ $RECURSIVE -eq 0 ]] && depth_arg="-d 1"
  local -a exts=(jpg jpeg png gif svg webp avif jxl tiff tif bmp mp4 mkv mov webm avi flv opus flac mp3 m4a aac ogg wav)
  if has fdf; then
    local -a args=(-tf --no-require-git $depth_arg)
    for e in "${exts[@]}"; do args+=(-e "$e"); done
    "${TOOLS[fdf]}" "${args[@]}" "$dir" 2>/dev/null
  elif has fd fdfind; then
    local -a args=(-tf --no-require-git $depth_arg)
    for e in "${exts[@]}"; do args+=(-e "$e"); done
    "${TOOLS[fd]}" "${args[@]}" "$dir" 2>/dev/null
  else
    local -a args=(-type f) pats=()
    [[ $RECURSIVE -eq 0 ]] && args+=(-maxdepth 1)
    for e in "${exts[@]}"; do pats+=(-o -iname "*.$e"); done
    find "$dir" "${args[@]}" \( "${pats[@]:1}" \) 2>/dev/null
  fi
}
# -- Output path resolution --
get_output(){
  local src=$1 fmt=$2 dir=${OUTPUT_DIR:-$(dirname "$src")}
  local base=$(basename "$src") name="${base%.*}" ext="${base##*.}"
  if [[ -n $fmt && $fmt != "${ext,,}" ]]; then
    echo "$dir/${name}.${fmt}"
  elif [[ $INPLACE -eq 1 ]]; then
    echo "$src"
  else
    echo "$dir/${name}${SUFFIX}.${ext}"
  fi
}
# -- Already optimized check --
is_optimized(){
  local f=$1 ext="${1##*.}" && ext="${ext,,}"
  [[ $f == *"$SUFFIX"* ]] && return 0
  case $ext in
    webp|avif|jxl) return 0;;
    jpg|jpeg) 
      has identify || return 1
      local q=$("${TOOLS[identify]}" -format '%Q' "$f" 2>/dev/null || echo 100)
      ((q<90));;
    *) return 1;;
  esac
}
# -- Image optimization --
optimize_image(){
  local src=$1 ext="${src##*.}" && ext="${ext,,}"
  local fmt=${FORMAT:-$ext} out
  # Skip check
  [[ $SKIP_OPT -eq 1 ]] && is_optimized "$src" && { ((SKIPPED++)); return 0; }
  # Output path
  out=$(get_output "$src" "$fmt")
  [[ -f $out && $KEEP_ORIG -eq 1 && $INPLACE -eq 0 ]] && { ((SKIPPED++)); return 0; }
  # Dry run
  [[ $DRY_RUN -eq 1 ]] && { log "[DRY] $(basename "$src") → $fmt"; return 0; }
  local tmp="${src}.tmp"
  cp "$src" "$tmp" || return 1
  # Format conversion
  if [[ $fmt != "$ext" ]]; then
    case $fmt in
      webp)
        if has cwebp; then
          [[ $LOSSLESS -eq 1 ]] && cwebp -lossless "$tmp" -o "${tmp}.out" &>/dev/null || \
          cwebp -q "$QUALITY" -m 6 "$tmp" -o "${tmp}.out" &>/dev/null
        fi;;
      avif) has avifenc && avifenc -s 6 -j "$(nproc)" --min 0 --max 60 "$tmp" "${tmp}.out" &>/dev/null;;
      jxl)
        has cjxl && {
          [[ $LOSSLESS -eq 1 ]] && cjxl "$tmp" "${tmp}.out" -d 0 -e 7 &>/dev/null || \
          cjxl "$tmp" "${tmp}.out" -q "$QUALITY" -e 7 &>/dev/null
        };;
    esac
    [[ -f "${tmp}.out" ]] && mv "${tmp}.out" "$out" || { rm -f "$tmp" "${tmp}.out"; return 1; }
    rm -f "$tmp"
  else
    # In-format optimization
    case $ext in
      png)
        has oxipng && oxipng -o max -q "$tmp" &>/dev/null
        [[ $LOSSLESS -eq 0 ]] && has pngquant && pngquant --quality="$QUALITY"-100 -f "$tmp" -o "${tmp}.2" &>/dev/null && mv "${tmp}.2" "$tmp";;
      jpg|jpeg) has jpegoptim && jpegoptim $([ $LOSSLESS -eq 0 ] && echo "--max=$QUALITY") -q -f --stdout "$tmp" >"${tmp}.2" 2>/dev/null && mv "${tmp}.2" "$tmp";;
      gif)
        has gifsicle && gifsicle -O3 "$tmp" -o "${tmp}.2" &>/dev/null && mv "${tmp}.2" "$tmp";;
      svg)
        has svgo && svgo -i "$tmp" -o "${tmp}.2" &>/dev/null && mv "${tmp}.2" "$tmp";;
    esac
    # Atomic replace for in-place
    if [[ $INPLACE -eq 1 ]]; then
      mv -f "$tmp" "$src"
    else
      mv -f "$tmp" "$out"
    fi
  fi
  # Stats
  local orig=$(stat -c%s "$src" 2>/dev/null || echo 0)
  local new=$(stat -c%s "$out" 2>/dev/null || echo 0)
  if ((new>0 && new<orig)); then
    local saved=$((orig-new)) pct=$((saved*100/orig))
    ((MIN_SAVE>0 && pct<MIN_SAVE)) && { rm -f "$out"; ((SKIPPED++)); return 1; }
    ((PROCESSED++))
    printf '%s → %s (%d%%)\n' "$(basename "$src")" "$(basename "$out")" "$pct"
    [[ $INPLACE -eq 0 && $KEEP_ORIG -eq 0 ]] && [[ $src != "$out" ]] && rm -f "$src"
  else
    [[ $fmt == "$ext" ]] && { rm -f "$out"; ((FAILED++)); return 1; }
    ((PROCESSED++))
  fi
}

# -- Video optimization --
optimize_video(){
  local src=$1 ext="${src##*.}" out=$(get_output "$src" "$ext")
  [[ -f $out && $KEEP_ORIG -eq 1 && $INPLACE -eq 0 ]] && return 0
  [[ $DRY_RUN -eq 1 ]] && { log "[DRY] $(basename "$src")"; return 0; }
  # Detect best codec
  local vcodec=""
  if has ffmpeg; then
    local encoders=$("${TOOLS[ffmpeg]}" -hide_banner -encoders 2>/dev/null || :)
    if [[ $encoders == *libsvtav1* ]]; then vcodec="libsvtav1"
    elif [[ $encoders == *libaom-av1* ]]; then vcodec="libaom-av1"  
    elif [[ $encoders == *libvpx-vp9* ]]; then vcodec="libvpx-vp9"
    elif [[ $encoders == *libx265* ]]; then vcodec="libx265"
    else vcodec="libx264"; fi
  fi
  # Build ffmpeg args
  local -a vargs aargs=(-c:a libopus -b:a "${AUDIO_BITRATE}k")
  case $vcodec in
    libsvtav1) vargs=(-c:v libsvtav1 -preset 8 -crf "$VIDEO_CRF");;
    libaom-av1) vargs=(-c:v libaom-av1 -cpu-used 6 -crf "$VIDEO_CRF");;
    libvpx-vp9) vargs=(-c:v libvpx-vp9 -crf "$VIDEO_CRF" -b:v 0 -row-mt 1);;
    libx265) vargs=(-c:v libx265 -preset medium -crf "$VIDEO_CRF");;
    *) vargs=(-c:v libx264 -preset medium -crf "$VIDEO_CRF");;
  esac
  local tmp="${out}.tmp"
  if has ffzap; then
    "${TOOLS[ffzap]}" -i "$src" -f "${vargs[*]} ${aargs[*]} -y" -o "$tmp" --overwrite &>/dev/null
  elif has ffmpeg; then
    "${TOOLS[ffmpeg]}" -i "$src" "${vargs[@]}" "${aargs[@]}" -y "$tmp" &>/dev/null
  else
    warn "No video encoder"; return 1
  fi
  [[ -f $tmp ]] && mv "$tmp" "$out" || { rm -f "$tmp"; return 1; }
  local orig=$(stat -c%s "$src" 2>/dev/null || echo 0)
  local new=$(stat -c%s "$out" 2>/dev/null || echo 0)
  ((new>0 && new<orig)) && {
    ((PROCESSED++))
    printf '%s → %s (%d%%)\n' "$(basename "$src")" "$(basename "$out")" "$((100-new*100/orig))"
    [[ $INPLACE -eq 1 || $KEEP_ORIG -eq 0 ]] && [[ $src != "$out" ]] && rm -f "$src"
  } || { rm -f "$out"; ((FAILED++)); }
}

# -- Audio optimization --
optimize_audio(){
  local src=$1 ext="${src##*.}" out
  [[ $ext == "opus" ]] && out=$(get_output "$src" "$ext") || out=$(get_output "$src" "opus")
  [[ -f $out && $KEEP_ORIG -eq 1 && $INPLACE -eq 0 ]] && return 0
  [[ $DRY_RUN -eq 1 ]] && { log "[DRY] $(basename "$src") → opus"; return 0; }
  local tmp="${out}.tmp"
  if [[ $ext != "opus" ]]; then
    if has opusenc && [[ $ext =~ ^(wav|flac|aiff)$ ]]; then
      opusenc --bitrate "$AUDIO_BITRATE" --quiet "$src" "$tmp" &>/dev/null
    elif has ffmpeg; then
      "${TOOLS[ffmpeg]}" -i "$src" -c:a libopus -b:a "${AUDIO_BITRATE}k" -y "$tmp" &>/dev/null
    else
      warn "No audio encoder"; return 1
    fi
  else
    cp -f "$src" "$tmp"
  fi
  [[ -f $tmp ]] && mv "$tmp" "$out" || { rm -f "$tmp"; return 1; }
  local orig=$(stat -c%s "$src" 2>/dev/null || echo 0)
  local new=$(stat -c%s "$out" 2>/dev/null || echo 0)
  ((new<orig)) && {
    ((PROCESSED++))
    printf '%s → opus (%d%%)\n' "$(basename "$src")" "$((100-new*100/orig))"
    [[ $INPLACE -eq 1 || $KEEP_ORIG -eq 0 ]] && [[ $src != "$out" ]] && rm -f "$src"
  } || ((FAILED++))
}

# -- Process dispatcher --
process_file(){
  local f=$1 ext="${f##*.}" && ext="${ext,,}"
  ((TOTAL++))
  case $ext in
    jpg|jpeg|png|gif|svg|webp|avif|jxl|tiff|tif|bmp) [[ $MEDIA_TYPE =~ ^(all|image)$ ]] && optimize_image "$f";;
    mp4|mkv|mov|webm|avi|flv) [[ $MEDIA_TYPE =~ ^(all|video)$ ]] && optimize_video "$f";;
    opus|flac|mp3|m4a|aac|ogg|wav) [[ $MEDIA_TYPE =~ ^(all|audio)$ ]] && optimize_audio "$f";;
    *) ((SKIPPED++));;
  esac
}

# -- Main --
main(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) cat <<'EOF'
optimize - Media optimizer (images/video/audio)

USAGE: optimize [OPTIONS] [files/dirs...]

OPTIONS:
  -t TYPE   Media type: all|image|video|audio (default: all)
  -q N      Quality 1-100 (default: 85)
  -c N      Video CRF 0-51 (default: 27)
  -b N      Audio bitrate kbps (default: 128)
  -f FMT    Convert format (webp|avif|jxl|png|jpg)
  -o DIR    Output directory
  -k        Keep originals
  -i        Replace in-place
  -r        Recursive
  -j N      Parallel jobs (default: auto)
  -l        Lossy mode
  -n        Dry-run
  -s        Skip already optimized
  -T        TUI mode (interactive)
  --min N   Min % savings (default: 0)

EXAMPLES:
  optimize .
  optimize -f webp -q 90 -r ~/Pictures
  optimize -t video -c 28 video.mp4
EOF
        exit 0;;
      -t) MEDIA_TYPE="${2,,}"; shift 2;;
      -q) QUALITY=$2; shift 2;;
      -c) VIDEO_CRF=$2; shift 2;;
      -b) AUDIO_BITRATE=$2; shift 2;;
      -f) FORMAT="${2,,}"; LOSSLESS=0; shift 2;;
      -o) OUTPUT_DIR=$2; shift 2;;
      -k) KEEP_ORIG=1; shift;;
      -i) INPLACE=1; KEEP_ORIG=0; shift;;
      -r) RECURSIVE=1; shift;;
      -j) JOBS=$2; shift 2;;
      -l) LOSSLESS=0; shift;;
      -n) DRY_RUN=1; shift;;
      -s) SKIP_OPT=1; shift;;
      -T) TUI=1; shift;;
      --min) MIN_SAVE=$2; shift 2;;
      -*) die "Unknown option: $1";;
      *) break;;
    esac
  done
  # Validate
  ((QUALITY<1 || QUALITY>100)) && die "Quality must be 1-100"
  ((VIDEO_CRF<0 || VIDEO_CRF>51)) && die "CRF must be 0-51"
  ((AUDIO_BITRATE<6 || AUDIO_BITRATE>510)) && die "Bitrate must be 6-510"
  [[ -n $OUTPUT_DIR ]] && mkdir -p "$OUTPUT_DIR"
  # Collect files
  local -a files=()
  if [[ $TUI -eq 1 ]]; then
    has sk || has fzf || die "TUI requires sk or fzf"
    local picker=${TOOLS[sk]:-${TOOLS[fzf]}}
    mapfile -t files < <(find_media "${1:-.}" | "$picker" -m --height=~80% --layout=reverse)
  elif [[ $# -eq 0 || ($# -eq 1 && $1 == "-") ]]; then
    mapfile -t files
  else
    for arg in "$@"; do
      if [[ -f $arg ]]; then
        files+=("$arg")
      elif [[ -d $arg ]]; then
        mapfile -t -O "${#files[@]}" files < <(find_media "$arg")
      fi
    done
  fi
  [[ ${#files[@]} -eq 0 ]] && die "No files found"
  # Process
  log "Processing ${#files[@]} files | Jobs: $JOBS | Mode: $([[ $LOSSLESS -eq 1 ]] && echo Lossless || echo "Lossy Q=$QUALITY")"
  if ((JOBS>1)) && has rust-parallel; then
    printf '%s\0' "${files[@]}" | "${TOOLS[rust-parallel]}" -0 --no-run-if-empty bash -c 'source "$1"; process_file "$2"' _ "$0" {}
  elif ((JOBS>1)) && has parallel; then  
    export -f process_file optimize_image optimize_video optimize_audio get_output is_optimized has
    export TOOLS QUALITY VIDEO_CRF AUDIO_BITRATE LOSSLESS FORMAT OUTPUT_DIR INPLACE KEEP_ORIG MIN_SAVE SKIP_OPT DRY_RUN MEDIA_TYPE SUFFIX
    printf '%s\0' "${files[@]}" | "${TOOLS[parallel]}" -0 -j "$JOBS" process_file {}
  else
    for f in "${files[@]}"; do process_file "$f"; done
  fi
  # Stats
  log "" "Complete: Processed=$PROCESSED Skipped=$SKIPPED Failed=$FAILED"
}

main "$@"
