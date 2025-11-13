#!/usr/bin/env bash
set -Eeuo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'; export LC_ALL=C LANG=C

# -- Colors --
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' X=$'\e[0m'

# -- Config --
declare -gi QUALITY=85 VIDEO_CRF=27 AUDIO_BR=128 ZOPFLI_ITER=60
declare -gi LOSSLESS=0 DRY=0 KEEP=0 JOBS=0 FFZAP_THREADS=2
declare -g OUTDIR="" TYPE="all" SUFFIX="_opt"
declare -g IMG_FMT="webp" VID_CODEC="av1"
declare -gi TOTAL=0 OK=0 SKIP=0 FAIL=0

# -- Helpers --
die(){ printf '%s%s%s\n' "$R" "$*" "$X" >&2; exit 1; }
warn(){ printf '%s%s%s\n' "$Y" "$*" "$X" >&2; }
log(){ printf '%s\n' "$*"; }
has(){ command -v "$1" &>/dev/null; }

# -- Cleanup --
TMPDIR=$(mktemp -d)
cleanup(){ rm -rf "$TMPDIR"; }
trap cleanup EXIT

# -- Find files (filtered, recursive) --
find_files(){
  local dir=${1:-.}
  local -a img=(jpg jpeg png gif webp avif jxl tiff bmp)
  local -a vid=(mp4 mkv mov webm avi flv)
  local -a aud=(opus flac mp3 m4a aac ogg wav)
  local -a exts=()
  case $TYPE in
    all) exts=("${img[@]}" "${vid[@]}" "${aud[@]}");;
    image) exts=("${img[@]}");;
    video) exts=("${vid[@]}");;
    audio) exts=("${aud[@]}");;
  esac
  if has fd; then
    local -a args=(-tf --no-require-git -S+10k)
    for e in "${exts[@]}"; do args+=(-e "$e"); done
    fd "${args[@]}" "$dir" 2>/dev/null | grep -v "$SUFFIX"
  else
    find "$dir" -type f ! -name "*${SUFFIX}*" -size +10k \( \
      $(printf -- "-o -iname *.%s " "${exts[@]}") \
    \) 2>/dev/null | sed 's/^-o //'
  fi
}

# -- Output path --
outpath(){
  local src=$1 fmt=${2:-${src##*.}}
  local dir=${OUTDIR:-$(dirname "$src")}
  local base=$(basename "$src") name="${base%.*}"
  echo "$dir/${name}${SUFFIX}.${fmt}"
}

# -- Image optimization --
opt_image(){
  local src=$1 ext="${src##*.}" && ext="${ext,,}"
  local out=$(outpath "$src" "$IMG_FMT")
  [[ -f $out && $KEEP -eq 1 ]] && { ((SKIP++)); return 0; }
  [[ $DRY -eq 1 ]] && { log "[DRY] $(basename "$src") → $IMG_FMT"; return 0; }
  local tmp="$TMPDIR/$(basename "$src")"
  cp "$src" "$tmp" || return 1
  # Format conversion + optimization
  if [[ $IMG_FMT != "$ext" ]]; then
    if has rimage; then
      local cmd="$IMG_FMT"
      [[ $IMG_FMT == "webp" ]] && cmd="mozjpeg"
      [[ $LOSSLESS -eq 0 ]] && rimage "$cmd" -q "$QUALITY" -d "$TMPDIR" "$tmp" &>/dev/null || { rm -f "$tmp"; return 1; }
      [[ $LOSSLESS -eq 1 ]] && rimage "$cmd" -d "$TMPDIR" "$tmp" &>/dev/null || { rm -f "$tmp"; return 1; }
      local converted="$TMPDIR/$(basename "$src" ."$ext").$IMG_FMT"
      [[ -f $converted ]] && mv "$converted" "$out" || { rm -f "$tmp"; return 1; }
    else
      case $IMG_FMT in
        webp)
          has cwebp && {
            [[ $LOSSLESS -eq 1 ]] && cwebp -lossless "$tmp" -o "$out" &>/dev/null || \
            cwebp -q "$QUALITY" -m 6 "$tmp" -o "$out" &>/dev/null
          };;
        avif) has avifenc && avifenc -s 6 -j "$JOBS" --min 0 --max 60 "$tmp" "$out" &>/dev/null;;
        jxl)
          has cjxl && {
            [[ $LOSSLESS -eq 1 ]] && cjxl "$tmp" "$out" -d 0 -e 7 &>/dev/null || \
            cjxl "$tmp" "$out" -q "$QUALITY" -e 7 &>/dev/null
          };;
      esac
    fi
    rm -f "$tmp"
  else
    # In-format optimization
    if [[ $LOSSLESS -eq 1 ]]; then
      if has flaca; then
        flaca -j1 "$tmp" &>/dev/null || { rm -f "$tmp"; return 1; }
      else
        case $ext in
          png)
            has oxipng && oxipng -o max -q "$tmp" &>/dev/null
            has optipng && optipng -o7 -quiet "$tmp" &>/dev/null;;
          jpg|jpeg) has jpegoptim && jpegoptim --strip-all -q "$tmp" &>/dev/null;;
          webp) has cwebp && { local t="${tmp}.webp"; cwebp -lossless "$tmp" -o "$t" &>/dev/null && mv "$t" "$tmp"; };;
        esac
      fi
    else
      if has rimage; then
        rimage mozjpeg -q "$QUALITY" -d "$TMPDIR" "$tmp" &>/dev/null || { rm -f "$tmp"; return 1; }
        local opt="$TMPDIR/$(basename "$tmp")"
        [[ -f $opt ]] && mv "$opt" "$tmp"
      else
        case $ext in
          png)
            has oxipng && oxipng -o max -q "$tmp" &>/dev/null
            has pngquant && pngquant --quality="$QUALITY"-100 -f "$tmp" -o "${tmp}.2" &>/dev/null && mv "${tmp}.2" "$tmp";;
          jpg|jpeg) has jpegoptim && jpegoptim --max="$QUALITY" -q -f "$tmp" &>/dev/null;;
          webp) has cwebp && { local t="${tmp}.webp"; cwebp -q "$QUALITY" -m 6 "$tmp" -o "$t" &>/dev/null && mv "$t" "$tmp"; };;
        esac
      fi
    fi
    mv "$tmp" "$out"
  fi
  [[ -f $out ]] || { ((FAIL++)); return 1; }
  local orig=$(stat -c%s "$src" 2>/dev/null || echo 0)
  local new=$(stat -c%s "$out" 2>/dev/null || echo 0)
  if ((new>0 && new<orig)); then
    printf '%s → %d%%\n' "$(basename "$src")" "$((100-new*100/orig))"
    [[ $KEEP -eq 0 ]] && rm -f "$src"
    ((OK++))
  else
    rm -f "$out"
    ((SKIP++))
  fi
}

# -- Video optimization --
opt_video(){
  local src=$1 out=$(outpath "$src")
  [[ -f $out && $KEEP -eq 1 ]] && { ((SKIP++)); return 0; }
  [[ $DRY -eq 1 ]] && { log "[DRY] $(basename "$src")"; return 0; }
  has ffmpeg || { warn "ffmpeg missing"; ((FAIL++)); return 1; }
  # Detect codec
  local enc=$(ffmpeg -hide_banner -encoders 2>/dev/null)
  local vc="libx264"
  case $VID_CODEC in
    av1)
      [[ $enc == *libsvtav1* ]] && vc="libsvtav1" || \
      [[ $enc == *libaom-av1* ]] && vc="libaom-av1";;
    vp9) [[ $enc == *libvpx-vp9* ]] && vc="libvpx-vp9";;
    h265) [[ $enc == *libx265* ]] && vc="libx265";;
    h264) vc="libx264";;
  esac
  local -a vargs=() aargs=(-c:a libopus -b:a "${AUDIO_BR}k")
  case $vc in
    libsvtav1) vargs=(-c:v libsvtav1 -preset 8 -crf "$VIDEO_CRF");;
    libaom-av1) vargs=(-c:v libaom-av1 -cpu-used 6 -crf "$VIDEO_CRF");;
    libvpx-vp9) vargs=(-c:v libvpx-vp9 -crf "$VIDEO_CRF" -b:v 0 -row-mt 1);;
    libx265) vargs=(-c:v libx265 -preset medium -crf "$VIDEO_CRF");;
    *) vargs=(-c:v libx264 -preset medium -crf "$VIDEO_CRF");;
  esac
  local tmp="$TMPDIR/$(basename "$out")"
  if has ffzap; then
    ffzap -i "$src" -f "${vargs[*]} ${aargs[*]}" -o "$tmp" -t "$FFZAP_THREADS" --overwrite &>/dev/null
  elif has ffmpeg; then
    ffmpeg -i "$src" "${vargs[@]}" "${aargs[@]}" -y "$tmp" &>/dev/null
  else
    return 1
  fi
  [[ -f $tmp ]] || { ((FAIL++)); return 1; }
  local orig=$(stat -c%s "$src" 2>/dev/null || echo 0)
  local new=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
  if ((new>0 && new<orig)); then
    mv "$tmp" "$out"
    printf '%s → %d%%\n' "$(basename "$src")" "$((100-new*100/orig))"
    [[ $KEEP -eq 0 ]] && rm -f "$src"
    ((OK++))
  else
    rm -f "$tmp"
    ((SKIP++))
  fi
}

# -- Audio optimization --
opt_audio(){
  local src=$1 ext="${src##*.}"
  local out=$(outpath "$src" "opus")
  [[ $ext == "opus" ]] && { ((SKIP++)); return 0; }
  [[ -f $out && $KEEP -eq 1 ]] && { ((SKIP++)); return 0; }
  [[ $DRY -eq 1 ]] && { log "[DRY] $(basename "$src") → opus"; return 0; }
  has ffmpeg || { warn "ffmpeg missing"; ((FAIL++)); return 1; }
  local tmp="$TMPDIR/$(basename "$out")"
  if has ffzap; then
    ffzap -i "$src" -f "-c:a libopus -b:a ${AUDIO_BR}k" -o "$tmp" -t "$FFZAP_THREADS" --overwrite &>/dev/null
  elif has ffmpeg; then
    ffmpeg -i "$src" -c:a libopus -b:a "${AUDIO_BR}k" -y "$tmp" &>/dev/null
  else
    return 1
  fi
  [[ -f $tmp ]] || { ((FAIL++)); return 1; }
  local orig=$(stat -c%s "$src" 2>/dev/null || echo 0)
  local new=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
  if ((new>0 && new<orig)); then
    mv "$tmp" "$out"
    printf '%s → opus %d%%\n' "$(basename "$src")" "$((100-new*100/orig))"
    [[ $KEEP -eq 0 ]] && rm -f "$src"
    ((OK++))
  else
    rm -f "$tmp"
    ((SKIP++))
  fi
}

# -- Dispatcher --
process(){
  local f=$1 ext="${f##*.}" && ext="${ext,,}"
  ((TOTAL++))
  case $ext in
    jpg|jpeg|png|gif|webp|avif|jxl|tiff|bmp) [[ $TYPE =~ ^(all|image)$ ]] && opt_image "$f";;
    mp4|mkv|mov|webm|avi|flv) [[ $TYPE =~ ^(all|video)$ ]] && opt_video "$f";;
    opus|flac|mp3|m4a|aac|ogg|wav) [[ $TYPE =~ ^(all|audio)$ ]] && opt_audio "$f";;
    *) ((SKIP++));;
  esac
}

# -- Main --
main(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) cat <<'EOF'
optimize - Media optimizer (recursive, filtered)

USAGE: optimize [OPTIONS] [paths...]

OPTIONS:
  -t TYPE      Type: all|image|video|audio (default: all)
  -q N         Quality 1-100 (default: 85)
  -c N         Video CRF 0-51 (default: 27)
  -b N         Audio bitrate kbps (default: 128)
  -o DIR       Output directory
  -k           Keep originals
  -j N         Parallel jobs (0=auto, default: 0)
  -l           Lossless mode
  -n           Dry-run
  --img FMT    Image format: webp|avif|jxl|png|jpg (default: webp)
  --vid CODEC  Video codec: av1|vp9|h265|h264 (default: av1)
  --zopfli N   Zopfli iterations (default: 60)
  --ffzap-t N  ffzap threads (default: 2)

FILTERS: Always recursive, min 10KB, excludes *_opt* paths
PARALLEL: rust-parallel → parallel → xargs
TOOLS: flaca, rimage, ffzap, ffmpeg, oxipng, optipng, pngquant, jpegoptim, cwebp, avifenc, cjxl
EOF
        exit 0;;
      -t) TYPE="${2,,}"; shift 2;;
      -q) QUALITY=$2; shift 2;;
      -c) VIDEO_CRF=$2; shift 2;;
      -b) AUDIO_BR=$2; shift 2;;
      -o) OUTDIR=$2; shift 2;;
      -k) KEEP=1; shift;;
      -j) JOBS=$2; shift 2;;
      -l) LOSSLESS=1; shift;;
      -n) DRY=1; shift;;
      --img) IMG_FMT="${2,,}"; shift 2;;
      --vid) VID_CODEC="${2,,}"; shift 2;;
      --zopfli) ZOPFLI_ITER=$2; shift 2;;
      --ffzap-t) FFZAP_THREADS=$2; shift 2;;
      -*) die "Unknown: $1";;
      *) break;;
    esac
  done
  ((QUALITY<1 || QUALITY>100)) && die "Quality: 1-100"
  ((VIDEO_CRF<0 || VIDEO_CRF>51)) && die "CRF: 0-51"
  [[ -n $OUTDIR ]] && mkdir -p "$OUTDIR"
  [[ $JOBS -eq 0 ]] && JOBS=$(nproc)
  local -a files=()
  if [[ $# -eq 0 ]]; then
    mapfile -t files < <(find_files .)
  else
    for p in "$@"; do
      [[ -f $p ]] && files+=("$p") || mapfile -t -O "${#files[@]}" files < <(find_files "$p")
    done
  fi
  [[ ${#files[@]} -eq 0 ]] && die "No files"
  log "Files: ${#files[@]} | Jobs: $JOBS | Mode: $([[ $LOSSLESS -eq 1 ]] && echo Lossless || echo "Lossy Q=$QUALITY") | Img: $IMG_FMT | Vid: $VID_CODEC"
  # Parallel execution: rust-parallel → parallel → xargs
  if ((JOBS>1)); then
    export -f process opt_image opt_video opt_audio outpath has
    export QUALITY VIDEO_CRF AUDIO_BR LOSSLESS OUTDIR KEEP DRY TYPE SUFFIX TMPDIR R G Y X IMG_FMT VID_CODEC FFZAP_THREADS ZOPFLI_ITER
    export OK SKIP FAIL TOTAL
    if has rust-parallel; then
      printf '%s\0' "${files[@]}" | rust-parallel -0 -j "$JOBS" bash -c 'source <(declare -f process opt_image opt_video opt_audio outpath has); process "$1"' _ {}
    elif has parallel; then
      printf '%s\0' "${files[@]}" | parallel -0 -j "$JOBS" --no-notice process {}
    else
      printf '%s\0' "${files[@]}" | xargs -0 -r -P "$JOBS" -n1 bash -c 'source <(declare -f process opt_image opt_video opt_audio outpath has); process "$1"' _
    fi
  else
    for f in "${files[@]}"; do process "$f"; done
  fi
  log "Done: OK=$OK Skip=$SKIP Fail=$FAIL"
}

main "$@"
