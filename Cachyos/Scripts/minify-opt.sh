#!/usr/bin/env bash
set -euo pipefail

# Disable unicode
# https://github.com/dylanaraps/pure-bash-bible?tab=readme-ov-file#performance
export LC_ALL=C LANG=C

# ─── USAGE ─────────────────────────────────────────────────────────────────────
if [ $# -ne 1 ]; then
  echo "Usage: $0 /path/to/directory"
  exit 1
fi
TARGET_DIR="$1"
[ -d "$TARGET_DIR" ] || { echo "Error: '$TARGET_DIR' is not a directory"; exit 1; }

# ─── SETUP ──────────────────────────────────────────────────────────────────────
BACKUP_DIR="$HOME/image_backups_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
LOGFILE="$HOME/image_compression_log.txt"
echo "Image compression started at $(date)" > "$LOGFILE"

# degree of parallelism; override by exporting JOBS in your env
JOBS=${JOBS:-"$(nproc)"}

# ─── FUNCTION ───────────────────────────────────────────────────────────────────
compress_image() {
  local file="$1"
  local lower="${file##*.}"
      lower="${lower,,}"     # extension in lowercase
  local backup="$BACKUP_DIR$file"
  mkdir -p "${backup%/*}"
  cp -p -- "$file" "$backup"

  local tmp

  case "$lower" in
    jpg|jpeg)
      jpegoptim --strip-all --all-progressive --quiet -- "$file"
      ;;
    png)
      tmp=$(mktemp --suffix=.png)
      if pngquant --strip --quality=60-85 --speed=1 --output "$tmp" -- "$file"; then
        oxipng -o max --strip all -a -i 0 --force -Z --zi 20 --out "$file" "$tmp"
      else
        oxipng -o max --strip all -a -i 0 --force -Z --zi 20 -- "$file"
      fi
      rm -f -- "${tmp:-}"
      ;;
    gif)
      gifsicle -O3 --batch --threads=16 -- "$file"
      ;;
    svg)
      svgo --multipass --quiet -- "$file"
      scour -i "$file" -o "$file.tmp" --enable-id-stripping --enable-comment-stripping
      mv -f -- "$file.tmp" "$file"
      ;;
    webp)
      tmp=$(mktemp --suffix=.webp)
      if cwebp -lossless -q 100 -- "$file" -o "$tmp"; then
        mv -f -- "$tmp" "$file"
      fi
      rm -f -- "${tmp:-}"
      ;;
    avif)
      tmp=$(mktemp --suffix=.avif)
      if avifenc --min 0 --max 0 --speed 8 -- "$file" "$tmp"; then
        mv -f -- "$tmp" "$file"
      fi
      rm -f -- "${tmp:-}"
      ;;
    jxl)
      tmp=$(mktemp --suffix=.jxl)
      if cjxl --lossless_jpeg=1 -- "$file" "$tmp"; then
        mv -f -- "$tmp" "$file"
      fi
      rm -f -- "${tmp:-}"
      ;;
    html|htm)
      minhtml --in-place -- "$file"
      ;;
    css)
      minhtml --in-place --minify-css -- "$file"
      ;;
    js)
      minhtml --in-place --minify-js -- "$file"
      ;;
    *)
      # unsupported extension
      return
      ;;
  esac

  printf '[%s] Compressed %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$file" \
    >> "$LOGFILE"
}

export -f compress_image
export BACKUP_DIR LOGFILE

# ─── FIND + DISPATCH ────────────────────────────────────────────────────────────
find "$TARGET_DIR" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
    -iname "*.svg" -o -iname "*.webp" -o -iname "*.avif" -o -iname "*.jxl" -o \
    -iname "*.html" -o -iname "*.htm" -o -iname "*.css" -o -iname "*.js" \
\) -print0 | {

  if command -v rust-parallel &>/dev/null; then
    # rust-parallel: fast, low-overhead
    rust-parallel --null-separator --jobs "$JOBS" -- \
      bash -c 'compress_image "$@"' _ {}

  elif command -v parallel &>/dev/null; then
    # GNU Parallel: robust, supports --no-notice & --line-buffer
    parallel -0 -j "$JOBS" --no-notice --line-buffer \
      bash -c 'compress_image "$@"' _ {}

  else
    # Pure-bash fallback: manual job control
    while IFS= read -r -d '' file; do
      (
        echo "Compressing: $file" >> "$LOGFILE"
        compress_image "$file"
      ) &

      # throttle background jobs
      while [ "$(jobs -pr | wc -l)" -ge "$JOBS" ]; do
        read -rt 0.1 <> <(:) || true
      done
    done
    wait
  fi
}

echo "Compression finished at $(date)" >> "$LOGFILE"
echo "Backups saved in: $BACKUP_DIR"
echo "Done. See log: $LOGFILE"
