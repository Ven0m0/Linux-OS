#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# tiny image optimizer: uses rust-parallel -s if present, else parallel, else xargs -P
JOBS=$(nproc 2>/dev/null || echo 4)
LOSSY=0; DRYRUN=0; KEEPBACKUP=0; TARGET="."

while (( $# )); do
  case "$1" in
    --lossy) LOSSY=1; shift;;
    --dry-run) DRYRUN=1; shift;;
    --keep-backup) KEEPBACKUP=1; shift;;
    -h|--help) printf 'Usage: %s [--lossy] [--dry-run] [--keep-backup] [path]\n' "$0"; exit 0;;
    --) shift; TARGET="$1"; shift; break;;
    -*) printf 'Unknown option: %s\n' "$1" >&2; exit 2;;
    *) TARGET="$1"; shift;;
  esac
done

FD=$(command -v fd || command -v fdfind || true)
HAS() { command -v "$1" >/dev/null 2>&1; }

TMPDIR="$(mktemp -d)"
OPT="$TMPDIR/optimize-single.sh"

cat >"$OPT" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
file="$1"; lossy="$2"; dry="$3"; keep="$4"
filesize(){ if stat -c%s "$1" >/dev/null 2>&1; then stat -c%s "$1"; else stat -f%z "$1"; fi }
replace_if_smaller(){
  o="$1"; c="$2"; [ -f "$c" ] || return 1
  old=$(filesize "$o"); new=$(filesize "$c")
  if [ "$new" -lt "$old" ]; then
    if [ "$dry" -eq 1 ]; then echo "[DRY] would replace: $o (saved $((old-new)) bytes)"; rm -f "$c"; return 0; fi
    [ "$keep" -eq 1 ] && cp -a -- "$o" "$o.bak" || true
    mv -f -- "$c" "$o"; echo "optimized: $o (saved $((old-new)) bytes)"; return 0
  fi
  rm -f -- "$c"; return 1
}
has(){ command -v "$1" >/dev/null 2>&1; }
ext="${file##*.}"; ext="${ext,,}"
tmpf="$(mktemp "${file}.XXXXXX")"
case "$ext" in
  png)
    [ "$lossy" -eq 1 ] && has pngquant && pngquant --quality=65-90 --speed=1 --strip --output "$tmpf" -- "$file" 2>/dev/null || true && replace_if_smaller "$file" "$tmpf" || true
    has oxipng && oxipng -o 6 --strip safe --out "$tmpf" "$file" 2>/dev/null || true && replace_if_smaller "$file" "$tmpf" || true
    has flaca && ( [ "$dry" -eq 1 ] && echo "[DRY] flaca $file" || flaca --no-symlinks --preserve-times "$file" >/dev/null 2>&1 || true )
    ;;
  jpg|jpeg)
    has flaca && ( [ "$dry" -eq 1 ] && echo "[DRY] flaca $file" || flaca --no-symlinks --preserve-times "$file" >/dev/null 2>&1 || true )
    if has jpegoptim; then
      if [ "$lossy" -eq 1 ]; then
        jpegoptim --strip-all --all-progressive --max=85 --stdin --stdout < "$file" > "$tmpf" 2>/dev/null || true
        replace_if_smaller "$file" "$tmpf" || true
      else
        [ "$dry" -eq 1 ] && echo "[DRY] jpegoptim --strip-all $file" || jpegoptim --strip-all --all-progressive --preserve "$file" >/dev/null 2>&1 || true
      fi
    fi
    ;;
  webp)
    [ "$lossy" -eq 1 ] && has cwebp && has dwebp && { dwebp "$file" -o "$tmpf.png" >/dev/null 2>&1 || true; cwebp -q 80 "$tmpf.png" -o "$tmpf" >/dev/null 2>&1 || true; rm -f "$tmpf.png"; replace_if_smaller "$file" "$tmpf" || true; }
    ;;
  avif)
    [ "$lossy" -eq 1 ] && has avifenc && avifenc --min 30 --max 40 --codec aom --speed 4 --output "$tmpf" "$file" >/dev/null 2>&1 || true && replace_if_smaller "$file" "$tmpf" || true
    ;;
  jxl)
    [ "$lossy" -eq 1 ] && has cjxl && cjxl "$file" "$tmpf" >/dev/null 2>&1 || true && replace_if_smaller "$file" "$tmpf" || true
    ;;
  gif)
    has gifsicle && ( [ "$dry" -eq 1 ] && echo "[DRY] gifsicle -O3 --batch $file" || gifsicle -O3 --batch "$file" >/dev/null 2>&1 || true )
    ;;
  svg)
    if has scour; then
      [ "$dry" -eq 1 ] && echo "[DRY] scour $file" || { scour -i "$file" -o "$tmpf" --enable-viewboxing --remove-metadata >/dev/null 2>&1 || true; replace_if_smaller "$file" "$tmpf" || true; }
    elif has svgo; then
      [ "$dry" -eq 1 ] && echo "[DRY] svgo $file" || { svgo "$file" -o "$tmpf" >/dev/null 2>&1 || true; replace_if_smaller "$file" "$tmpf" || true; }
    fi
    ;;
  html|htm)
    if has minify; then
      [ "$dry" -eq 1 ] && echo "[DRY] minify $file" || { minify --type html "$file" > "$tmpf" 2>/dev/null || true; replace_if_smaller "$file" "$tmpf" || true; }
    elif has html-minifier; then
      [ "$dry" -eq 1 ] && echo "[DRY] html-minifier $file" || { html-minifier --collapse-whitespace "$file" -o "$tmpf" 2>/dev/null || true; replace_if_smaller "$file" "$tmpf" || true; }
    fi
    ;;
esac
[ -f "$tmpf" ] && rm -f -- "$tmpf" || true
SH

chmod +x "$OPT"

emit(){
  if [ -n "$FD" ]; then "$FD" -0 -H -I -e png -e jpg -e jpeg -e webp -e avif -e jxl -e gif -e svg -e html . "$TARGET"
  else find "$TARGET" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.jxl' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.html' -o -iname '*.htm' \) -print0; fi
}

printf 'Target: %s\nJobs: %s\nLossy: %s\n' "$TARGET" "$JOBS" "$([ "$LOSSY" -eq 1 ] && echo yes || echo no)"
[ "$DRYRUN" -eq 1 ] && echo "DRY RUN - no files will be replaced"
[ "$KEEPBACKUP" -eq 1 ] && echo "Keeping backups as file.bak"

if HAS rust-parallel; then
  # feed newline-separated shell-escaped command lines into rust-parallel -s
  emit | while IFS= read -r -d '' f; do printf '%s\n' "$(printf '%q' "$OPT") $(printf '%q' "$f") $LOSSY $DRYRUN $KEEPBACKUP"; done | rust-parallel -j "$JOBS" -s
elif HAS parallel; then
  emit | parallel -0 -j "$JOBS" "$OPT" {} "$LOSSY" "$DRYRUN" "$KEEPBACKUP"
else
  emit | xargs -0 -P "$JOBS" -I {} bash -c '"$0" "$1" "$2" "$3" "$4"' "$OPT" {} "$LOSSY" "$DRYRUN" "$KEEPBACKUP"
fi

rm -rf "$TMPDIR"
echo Done.
