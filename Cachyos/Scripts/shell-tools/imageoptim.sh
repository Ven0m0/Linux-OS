#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C

# Usage
if [[ $# -lt 1 ]] || [[ ! -d $1 ]]; then
  echo "Usage: $0 /path/to/directory [--dry-run]" >&2
  exit 1
fi
TARGET_DIR="$1"
DRYRUN=0
if [[ ${2:-} == --dry-run ]]; then DRYRUN=1; fi

# Setup
BACKUP_DIR="$HOME/image_backups_$(date +%Y%m%d_%H%M%S)"
LOGFILE="$HOME/image_compression_log.txt"
mkdir -p "$BACKUP_DIR"
printf '%s\n' "Image compression started at $(date)" > "$LOGFILE"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
NPROC="$JOBS"
FD_EXTS=(jpg jpeg png gif svg webp avif jxl html htm css js)

# Export runtime flags so child shells see them
export BACKUP_DIR LOGFILE NPROC DRYRUN

# Helper: log message both to stdout and logfile (quiet when dry-run only)
log(){
  printf '[%s] %s\n' "$(date +'%F %T')" "$1" >> "$LOGFILE"
  printf '%s\n' "$1"
}

# compress_image: self-contained, local tmpfiles, auto-skip missing tools, honor DRYRUN
compress_image(){
  local file="$1" ext backup_dir tmpfile tmpdir
  ext="${file##*.}"
  ext="${ext,,}"
  backup_dir="$BACKUP_DIR/${-- "$file"%/*}"
  mkdir -p "$backup_dir"
  if [[ $DRYRUN -eq 1 ]]; then
    printf '[DRY] would backup %s -> %s\n' "$file" "$backup_dir/" >> "$LOGFILE"
  else
    cp -p -- "$file" "$backup_dir/" || printf '[WARN] backup failed: %s\n' "$file" >> "$LOGFILE"
  fi

  case "$ext" in
  jpg | jpeg)
    if command -v jpegoptim >/dev/null 2>&1; then
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] jpegoptim %s\n' "$file" >> "$LOGFILE"; else jpegoptim --strip-all --all-progressive --quiet -- "$file"; fi
    else
      printf '[SKIP] jpegoptim not found; skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  png)
    if command -v pngquant >/dev/null 2>&1; then
      tmpfile=$(mktemp --suffix=.png)
      if [[ $DRYRUN -eq 1 ]]; then
        printf '[DRY] pngquant %s -> tmp\n' "$file" >> "$LOGFILE"
      else
        if pngquant --strip --quality=60-85 --speed=1 --output "$tmpfile" -- "$file"; then
          if command -v oxipng >/dev/null 2>&1; then
            oxipng -o max --strip all -a -i 0 --scale16 --force -Z --zi 25 -j "$NPROC" --out "$file" "$tmpfile" || :
          else
            mv -f -- "$tmpfile" "$file"
          fi
        else
          rm -f -- "$tmpfile" || :
          if command -v oxipng >/dev/null 2>&1; then
            if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] oxipng (fallback) %s\n' "$file" >> "$LOGFILE"; else oxipng -o max --strip all -a -i 0 --force -Z --zi 20 -- "$file" || :; fi
          else
            printf '[SKIP] pngquant/oxipng missing; skipping %s\n' "$file" >> "$LOGFILE"
          fi
        fi
      fi
      rm -f -- "${tmpfile:-}" || :
    else
      if command -v oxipng >/dev/null 2>&1; then
        if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] oxipng %s\n' "$file" >> "$LOGFILE"; else oxipng -o max --strip all -a -i 0 --force -Z --zi 20 -- "$file" || :; fi
      else
        printf '[SKIP] no png optimizer found; skipping %s\n' "$file" >> "$LOGFILE"
      fi
    fi
    ;;
  gif)
    # Prefer gifsicle; if missing and gifski+ffmpeg exist, use ffmpeg->gifski pipeline
    if command -v gifsicle >/dev/null 2>&1; then
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] gifsicle %s\n' "$file" >> "$LOGFILE"; else gifsicle -O3 --batch -j"$NPROC" -- "$file" || printf '[WARN] gifsicle failed: %s\n' "$file" >> "$LOGFILE"; fi
    elif command -v gifski >/dev/null 2>&1 && command -v ffmpeg >/dev/null 2>&1; then
      tmpdir=$(mktemp -d)
      tmpfile=$(mktemp --suffix=.gif)
      if [[ $DRYRUN -eq 1 ]]; then
        printf '[DRY] ffmpeg -> gifski pipeline for %s (frames -> %s -> %s)\n' "$file" "$tmpdir" "$tmpfile" >> "$LOGFILE"
        rm -rf -- "$tmpdir"
      else
        # Extract frames (png) quietly
        ffmpeg -i "$file" -hide_banner -loglevel error "$tmpdir/frame%06d.png" || {
          printf '[WARN] ffmpeg failed for %s\n' "$file" >> "$LOGFILE"
          rm -rf -- "$tmpdir"
        }
        # Re-encode with gifski
        gifski -o "$tmpfile" "$tmpdir"/frame*.png >/dev/null 2>&1 || printf '[WARN] gifski failed for %s\n' "$file" >> "$LOGFILE"
        if [[ -f $tmpfile ]]; then mv -f -- "$tmpfile" "$file"; fi
        rm -rf -- "$tmpdir"
      fi
    else
      printf '[SKIP] no GIF tool (gifsicle or gifski+ffmpeg); skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  svg)
    if command -v svgo >/dev/null 2>&1; then
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] svgo %s\n' "$file" >> "$LOGFILE"; else svgo --multipass --quiet -- "$file" || :; fi
    elif command -v scour >/dev/null 2>&1; then
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] scour %s\n' "$file" >> "$LOGFILE"; else
        scour -i "$file" -o "$file.tmp" --enable-id-stripping --enable-comment-stripping || :
        mv -f -- "$file.tmp" "$file" 2>/dev/null || :
      fi
    else
      printf '[SKIP] no svg optimizer; skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  webp)
    if command -v cwebp >/dev/null 2>&1; then
      tmpfile=$(mktemp --suffix=.webp)
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] cwebp %s -> tmp\n' "$file" >> "$LOGFILE"; else cwebp -lossless -q 100 -- "$file" -o "$tmpfile" && mv -f -- "$tmpfile" "$file"; fi
      rm -f -- "${tmpfile:-}" || :
    else
      printf '[SKIP] cwebp missing; skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  avif)
    if command -v avifenc >/dev/null 2>&1; then
      tmpfile=$(mktemp --suffix=.avif)
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] avifenc %s -> tmp\n' "$file" >> "$LOGFILE"; else avifenc --min 0 --max 0 --speed 8 -- "$file" "$tmpfile" && mv -f -- "$tmpfile" "$file"; fi
      rm -f -- "${tmpfile:-}" || :
    else
      printf '[SKIP] avifenc missing; skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  jxl)
    if command -v cjxl >/dev/null 2>&1; then
      tmpfile=$(mktemp --suffix=.jxl)
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] cjxl %s -> tmp\n' "$file" >> "$LOGFILE"; else cjxl --lossless_jpeg=1 -- "$file" "$tmpfile" && mv -f -- "$tmpfile" "$file"; fi
      rm -f -- "${tmpfile:-}" || :
    else
      printf '[SKIP] cjxl missing; skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  html | htm)
    if command -v minhtml >/dev/null 2>&1; then
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] minhtml %s\n' "$file" >> "$LOGFILE"; else minhtml --in-place -- "$file"; fi
    else
      printf '[SKIP] minhtml missing; skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  css)
    if command -v minhtml >/dev/null 2>&1; then
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] minhtml --minify-css %s\n' "$file" >> "$LOGFILE"; else minhtml --in-place --minify-css -- "$file"; fi
    else
      printf '[SKIP] minify tool missing; skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  js)
    if command -v minhtml >/dev/null 2>&1; then
      if [[ $DRYRUN -eq 1 ]]; then printf '[DRY] minhtml --minify-js %s\n' "$file" >> "$LOGFILE"; else minhtml --in-place --minify-js -- "$file"; fi
    else
      printf '[SKIP] minify tool missing; skipping %s\n' "$file" >> "$LOGFILE"
    fi
    ;;
  *)
    printf '[SKIP] unsupported extension for %s\n' "$file" >> "$LOGFILE"
    ;;
  esac

  printf '[%s] Completed %s\n' "$(date +'%F %T')" "$file" >> "$LOGFILE"
}

export -f compress_image

# Build discovery command
if command -v fd >/dev/null 2>&1; then
  FD_CMD=(fd --type f "$(printf -- '--extension %s ' "${FD_EXTS[@]}")" '' "$TARGET_DIR" --print0)
else
  FIND_EXPR=()
  for e in "${FD_EXTS[@]}"; do FIND_EXPR+=(-iname "*.$e" -o); done
  FIND_EXPR=("${FIND_EXPR[@]::${#FIND_EXPR[@]}-1}")
  FD_CMD=(find "$TARGET_DIR" -type f \( "${FIND_EXPR[@]}" \) -print0)
fi

# Dispatch: rust-parallel -> xargs -> GNU parallel -> bash fallback
"${FD_CMD[@]}" | {
  if command -v rust-parallel >/dev/null 2>&1; then
    # Build newline-delimited, shell-quoted command lines (rust-parallel -s reads commands from stdin)
    while IFS= read -r -d '' f; do
      # include DRYRUN in environment via exported var; use printf '%q' to quote filename
      printf '%s\n' "compress_image $(printf '%q' "$f")"
    done | rust-parallel -s --jobs "$JOBS" --null-separator || :
    exit
  fi

  if command -v xargs >/dev/null 2>&1; then
    # xargs handles NULs safely; call compress_image in a bash -c so exported function is used
    xargs -0 -P "$JOBS" -I {} bash -lc 'compress_image "$@"' _ {} || :
    exit
  fi

  if command -v parallel >/dev/null 2>&1; then
    parallel -0 -j "$JOBS" --no-notice bash -c 'compress_image "$@"' _ {} || :
    exit
  fi

  # pure bash fallback
  while IFS= read -r -d '' f; do
    (
      printf '[%s] Compressing: %s\n' "$(date +'%F %T')" "$f" >> "$LOGFILE"
      compress_image "$f"
    ) &
    while [[ "$(jobs -pr | wc -l)" -ge $JOBS ]]; do wait -n || :; done
  done
  wait
}

printf '%s\n' "Compression finished at $(date)" >> "$LOGFILE"
printf 'Backups saved in: %s\n' "$BACKUP_DIR"
printf 'Done. See log: %s\n' "$LOGFILE"
