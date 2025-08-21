#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ----------------------------
# Simple image optimizer wrapper
# ----------------------------
# Usage:
#   ./optimize-images.sh [--jobs N] [--lossy] [--dry-run] [--keep-backup] [path]
# Defaults:
#   path = . (current directory)
#   jobs = number of CPU cores
#
# Behavior:
#  - Finds files by extension (png,jpg,jpeg,webp,avif,jxl,gif,svg,html)
#  - Runs a best-effort chain of optimizers depending on tool availability
#  - Replaces file only if the optimized output is smaller
#  - Prefers fd/fdfind for discovery; falls back to find
#  - Prefers rust-parallel if present; falls back to xargs -P
# ----------------------------

# Defaults
JOBS=$(nproc 2>/dev/null || echo 4)
LOSSY=0
DRYRUN=0
KEEPBACKUP=0
TARGET="."

# Parse args
while (( $# )); do
  case "$1" in
    --jobs) JOBS="$2"; shift 2;;
    --jobs=*) JOBS="${1#*=}"; shift;;
    --lossy) LOSSY=1; shift;;
    --dry-run) DRYRUN=1; shift;;
    --keep-backup) KEEPBACKUP=1; shift;;
    -h|--help) sed -n '1,120p' "$0"; exit 0;;
    --) shift; TARGET="$1"; shift; break;;
    -*)
      echo "Unknown option: $1" >&2; exit 2;;
    *)
      TARGET="$1"; shift;;
  esac
done

# Find fd / fdfind / find
if command -v fd >/dev/null 2>&1; then
  FD_BIN=fd
elif command -v fdfind >/dev/null 2>&1; then
  FD_BIN=fdfind
else
  FD_BIN=""
fi

# Choose parallel runner: prefer rust-parallel if available, else use xargs
if command -v rust-parallel >/dev/null 2>&1; then
  PARALLEL_BIN=rust-parallel
elif command -v parallel >/dev/null 2>&1; then
  PARALLEL_BIN=parallel
else
  PARALLEL_BIN=""
fi

TMPDIR="$(mktemp -d)"
OPT_SCRIPT="$TMPDIR/optimize-single.sh"

# helper to get file size portably
filesize_prog() {
  if stat -c%s "$1" >/dev/null 2>&1; then
    stat -c%s "$1"
  else
    stat -f%z "$1"
  fi
}

# Write the per-file optimization script (self-contained)
cat > "$OPT_SCRIPT" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
file="$1"
lossy_flag="$2"
dryrun="$3"
keepbackup="$4"
filesize_prog() {
  if stat -c%s "$1" >/dev/null 2>&1; then
    stat -c%s "$1"
  else
    stat -f%z "$1"
  fi
}
# Only replace original if optimized is smaller
replace_if_smaller() {
  orig="$1"
  candidate="$2"
  if [ ! -f "$candidate" ]; then return 1; fi
  old=$(filesize_prog "$orig")
  new=$(filesize_prog "$candidate")
  if [ "$new" -lt "$old" ]; then
    if [ "$dryrun" -eq 1 ]; then
      echo "[DRY] would replace: $orig (saved $((old-new)) bytes)"
      rm -f "$candidate"
      return 0
    fi
    if [ "$keepbackup" -eq 1 ]; then
      cp -a -- "$orig" "$orig.bak" || true
    fi
    mv -f -- "$candidate" "$orig"
    echo "optimized: $orig (saved $((old-new)) bytes)"
    return 0
  else
    rm -f -- "$candidate"
    return 1
  fi
}

# detect tools
has() { command -v "$1" >/dev/null 2>&1; }

ext="${file##*.}"
ext_l="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
tmpf="$(mktemp "${file}.XXXXXX")"

case "$ext_l" in
  png)
    # 1) pngquant (lossy) optionally
    if [ "$lossy_flag" -eq 1 ] && has pngquant; then
      pngquant --quality=65-90 --speed=1 --strip --output "$tmpf" -- "$file" >/dev/null 2>&1 || true
      replace_if_smaller "$file" "$tmpf" || true
    fi
    # 2) oxipng (lossless)
    if has oxipng; then
      # optimize into candidate
      oxipng -o 6 --strip safe --out "$tmpf" "$file" >/dev/null 2>&1 || true
      replace_if_smaller "$file" "$tmpf" || true
    fi
    # 3) flaca (lossless mega-opt) preference: run flaca over file (it writes in-place)
    if has flaca; then
      if [ "$dryrun" -eq 1 ]; then
        echo "[DRY] would run: flaca \"$file\""
      else
        flaca --no-symlinks --preserve-times "$file" >/dev/null 2>&1 || true
        echo "ran flaca: $file"
      fi
    fi
    ;;
  jpg|jpeg)
    # prefer flaca (lossless heavy) if available
    if has flaca; then
      if [ "$dryrun" -eq 1 ]; then
        echo "[DRY] would run: flaca \"$file\""
      else
        flaca --no-symlinks --preserve-times "$file" >/dev/null 2>&1 || true
        echo "ran flaca: $file"
      fi
    fi
    # jpegoptim: lossless Huffman optimization or lossy with --max
    if has jpegoptim; then
      if [ "$lossy_flag" -eq 1 ]; then
        jpegoptim --strip-all --all-progressive --max=85 --stdin --stdout < "$file" > "$tmpf" 2>/dev/null || true
        replace_if_smaller "$file" "$tmpf" || true
      else
        # lossless
        if [ "$dryrun" -eq 1 ]; then
          echo "[DRY] would run: jpegoptim --strip-all \"$file\""
        else
          jpegoptim --strip-all --all-progressive --preserve "$file" >/dev/null 2>&1 || true
        fi
      fi
    fi
    ;;
  webp)
    # For existing webp: try cwebp re-encode via dwebp/cwebp chain? skip for safety unless --lossy
    if [ "$lossy_flag" -eq 1 ] && has cwebp && has dwebp; then
      dwebp "$file" -o "$tmpf.png" >/dev/null 2>&1 || true
      cwebp -q 80 "$tmpf.png" -o "$tmpf" >/dev/null 2>&1 || true
      rm -f "$tmpf.png"
      replace_if_smaller "$file" "$tmpf" || true
    fi
    ;;
  avif)
    # AVIF: re-encode with avifenc if present (lossy). Avoid default unless --lossy.
    if [ "$lossy_flag" -eq 1 ] && has avifenc; then
      avifenc --min 30 --max 40 --codec aom --speed 4 --output "$tmpf" "$file" >/dev/null 2>&1 || true
      replace_if_smaller "$file" "$tmpf" || true
    fi
    ;;
  jxl|jxlx|jxl)
    # jpeg-xl: try cjxl if available (re-encode)
    if [ "$lossy_flag" -eq 1 ] && has cjxl; then
      cjxl "$file" "$tmpf" >/dev/null 2>&1 || true
      replace_if_smaller "$file" "$tmpf" || true
    fi
    ;;
  gif)
    if has gifsicle; then
      if [ "$dryrun" -eq 1 ]; then
        echo "[DRY] would run: gifsicle -O3 --batch \"$file\""
      else
        gifsicle -O3 --batch "$file" >/dev/null 2>&1 || true
        echo "ran gifsicle: $file"
      fi
    fi
    ;;
  svg)
    # scour or svgo
    if has scour; then
      if [ "$dryrun" -eq 1 ]; then
        echo "[DRY] would run: scour -i \"$file\" -o \"$tmpf\" --enable-viewboxing --remove-metadata"
      else
        scour -i "$file" -o "$tmpf" --enable-viewboxing --remove-metadata >/dev/null 2>&1 || true
        replace_if_smaller "$file" "$tmpf" || true
      fi
    elif has svgo; then
      if [ "$dryrun" -eq 1 ]; then
        echo "[DRY] would run: svgo \"$file\" -o \"$tmpf\""
      else
        svgo "$file" -o "$tmpf" >/dev/null 2>&1 || true
        replace_if_smaller "$file" "$tmpf" || true
      fi
    fi
    ;;
  html|htm)
    # html minify via 'minify' or 'html-minifier' if present
    if has minify; then
      if [ "$dryrun" -eq 1 ]; then
        echo "[DRY] would run: minify --type html \"$file\" > \"$tmpf\""
      else
        minify --type html "$file" > "$tmpf" 2>/dev/null || true
        replace_if_smaller "$file" "$tmpf" || true
      fi
    elif has html-minifier; then
      if [ "$dryrun" -eq 1 ]; then
        echo "[DRY] would run: html-minifier --collapse-whitespace \"$file\" -o \"$tmpf\""
      else
        html-minifier --collapse-whitespace "$file" -o "$tmpf" 2>/dev/null || true
        replace_if_smaller "$file" "$tmpf" || true
      fi
    fi
    ;;
  *)
    # Unknown extension; do nothing
    ;;
esac

# final cleanup
[ -f "$tmpf" ] && rm -f -- "$tmpf" || true
BASH

chmod +x "$OPT_SCRIPT"

# Build list command that emits null-separated file paths
emit_file_list() {
  if [ -n "$FD_BIN" ]; then
    # prefer fd/fdfind
    "$FD_BIN" -0 -H -I -e png -e jpg -e jpeg -e webp -e avif -e jxl -e gif -e svg -e html . "$TARGET"
  else
    # fallback to find
    find "$TARGET" -type f \( \
      -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o \
      -iname '*.avif' -o -iname '*.jxl' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.html' -o -iname '*.htm' \
    \) -print0
  fi
}

# Run
echo "Target: $TARGET"
echo "Jobs: $JOBS"
echo "Lossy conversions: $([ "$LOSSY" -eq 1 ] && echo yes || echo no)"
echo "Using fd: ${FD_BIN:-none}"
echo "Using parallel runner: ${PARALLEL_BIN:-xargs fallback}"
if [ "$DRYRUN" -eq 1 ]; then echo "DRY RUN - no files will be replaced"; fi
if [ "$KEEPBACKUP" -eq 1 ]; then echo "BACKUPS will be kept as file.bak"; fi

# Choose executor
if [ -n "$PARALLEL_BIN" ] && [ "$PARALLEL_BIN" = "rust-parallel" ]; then
  # rust-parallel expects an input file with command lines (one per line)
  CMDF="$TMPDIR/cmds.txt"
  : > "$CMDF"
  # construct safe shell-quoted command lines
  while IFS= read -r -d '' f; do
    # use printf %q for safe single-argument quoting
    esc=$(printf "%q" "$f")
    printf '%s\n' "\"$OPT_SCRIPT\" $esc" >> "$CMDF"
  done < <(emit_file_list)
  if [ "$DRYRUN" -eq 1 ]; then
    echo "[DRY] Would run rust-parallel reading commands from $CMDF (first lines):"
    head -n 6 "$CMDF"
  else
    rust-parallel -j "$JOBS" -i "$CMDF"
  fi

elif [ -n "$PARALLEL_BIN" ] && [ "$PARALLEL_BIN" != "rust-parallel" ]; then
  # GNU parallel
  if [ "$DRYRUN" -eq 1 ]; then
    echo "[DRY] Would run GNU parallel with $JOBS jobs"
    emit_file_list | tr '\0' '\n' | sed -n '1,6p'
  else
    emit_file_list | parallel -0 -j "$JOBS" "$OPT_SCRIPT" {}
  fi

else
  # fallback: xargs
  if [ "$DRYRUN" -eq 1 ]; then
    echo "[DRY] Would run xargs -P $JOBS"
    emit_file_list | tr '\0' '\n' | sed -n '1,6p'
  else
    # xargs -0 -P to run multiple jobs in parallel
    emit_file_list | xargs -0 -P "$JOBS" -I {} bash -c "$OPT_SCRIPT \"{}\" $LOSSY $DRYRUN $KEEPBACKUP"
  fi
fi

# cleanup
rm -rf "$TMPDIR"
echo "Done."
