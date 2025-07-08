#!/usr/bin/bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C LANG=C
shopt -s nullglob globstar

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

# degree of parallelism; override via JOBS env var
JOBS=${JOBS:-"$(nproc)"}

# ─── compress_image FUNCTION ──────────────────────────────────────────────────
compress_image() {
  local file="$1"
  local ext="${file##*.}"
       ext="${ext,,}"                      # lowercase extension
  local backup="$BACKUP_DIR$file"
  mkdir -p "${backup%/*}"
  cp -p -- "$file" "$backup"

  # Oxipng
  oxipng -o max --strip all -a -i 0 --scale16 --force -Z --zi 25 -j "$(nproc)" $TARGET_DIR
  
  local tmp
  case "$ext" in
    jpg|jpeg)
      jpegoptim --strip-all --all-progressive --quiet -- "$file"
      ;;
    png)
      tmp=$(mktemp --suffix=.png)
      if pngquant --strip --quality=60-85 --speed=1 --output "$tmp" -- "$file"; then
        oxipng -o max --strip all -a -i 0 --scale16 --force -Z --zi 25 -j "$(nproc)" --out "$file" "$tmp"
      else
        oxipng -o max --strip all -a -i 0 --force -Z --zi 20 -- "$file"
      fi
      rm -f -- "${tmp:-}"
      ;;
    gif)
      gifsicle -O3 --batch -j"$(nproc)" -- "$file"
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
      return
      ;;
  esac

  printf '[%s] Compressed %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$file" \
    >> "$LOGFILE"
}

export -f compress_image
export BACKUP_DIR LOGFILE

# ─── FILE DISCOVERY ────────────────────────────────────────────────────────────
if command -v fd &>/dev/null; then
  # fd: Rust-based, defaults to printing files only, recurse by default
  FD_CMD=(fd --type f --extension jpg --extension jpeg --extension png \
            --extension gif --extension svg --extension webp --extension avif \
            --extension jxl --extension html --extension htm --extension css \
            --extension js '' "$TARGET_DIR" --print0)
else
  # fallback to find
  FD_CMD=(find "$TARGET_DIR" -type f \( \
            -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
            -iname "*.svg" -o -iname "*.webp" -o -iname "*.avif" -o -iname "*.jxl" -o \
            -iname "*.html" -o -iname "*.htm" -o -iname "*.css" -o -iname "*.js" \
          \) -print0)
fi

# ─── DISPATCH ─────────────────────────────────────────────────────────────────
"${FD_CMD[@]}" | {
  if command -v rust-parallel &>/dev/null; then
    rust-parallel --null-separator --jobs "$JOBS" -- \
      bash -c 'compress_image "$@"' _ {}

  elif command -v parallel &>/dev/null; then
    parallel -0 -j "$JOBS" --no-notice --line-buffer \
      bash -c 'compress_image "$@"' _ {}

  else
    # Pure-bash fallback
    while IFS= read -r -d '' file; do
      (
        echo "Compressing: $file" >> "$LOGFILE"
        compress_image "$file"
      ) &
      # throttle via read
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
