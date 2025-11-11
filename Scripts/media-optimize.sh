#!/usr/bin/env bash
# Unified media optimizer — merges best parts of existing scripts (TUI, tool chains, parallelism)
# Targets: Arch/Debian/Termux. Safe defaults: backups, dry-run, replace only when smaller.
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# ---- UI / colors ----
if [[ -t 1 ]]; then
  RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' RST=$'\e[0m'
else
  RED= GRN= YLW= BLU= RST=
fi

# ---- cached tools (resolve once) ----
declare -A T
T[fd]="$(command -v fd || command -v fdfind || true)"
T[rg]="$(command -v rg || command -v grep || true)"
T[sk]="$(command -v sk || command -v fzf || true)"      # prefer sk (skim)
T[eza]="$(command -v eza || command -v ls || true)"     # prefer eza
T[rustp]="$(command -v rust-parallel || true)"
T[parallel]="$(command -v parallel || true)"
T[xargs]="$(command -v xargs || true)"
T[oxipng]="$(command -v oxipng || true)"
T[pngquant]="$(command -v pngquant || true)"
T[jpegoptim]="$(command -v jpegoptim || true)"
T[gifsicle]="$(command -v gifsicle || true)"
T[gifski]="$(command -v gifski || true)"
T[ffmpeg]="$(command -v ffmpeg || true)"
T[svgo]="$(command -v svgo || true)"
T[scour]="$(command -v scour || true)"
T[cwebp]="$(command -v cwebp || true)"
T[avifenc]="$(command -v avifenc || true)"
T[cjxl]="$(command -v cjxl || true)"
T[minify]="$(command -v minify || command -v html-minifier || true)"
T[rimage]="$(command -v rimage || true)"
T[flaca]="$(command -v flaca || true)"
T[simimg]="$(command -v simagef || command -v fclones || command -v jdupes || true)"

has(){ [[ -n ${T[$1]:-} ]]; }

# ---- defaults / config ----
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
DRYRUN=0
LOSSY=0
KEEP_BACKUPS=1
RECURSIVE=0
REPLACE_ORIG=0
WEBP_QUALITY=80
AVIF_SPEED=6
AVIF_QUAL=40
TARGET_DIR="."
LOGFILE="$HOME/media-optimize.log"

# ---- helpers ----
log(){ printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
die(){ printf '%s\n' "${RED}ERROR:${RST} $*" >&2; exit "${2:-1}"; }
filesize(){ stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0; }

mkbackup(){
  local file="$1" bakdir
  [[ $KEEP_BACKUPS -eq 0 ]] && return 0
  bakdir="$(dirname -- "$file")/.backups"
  mkdir -p "$bakdir"
  cp -p -- "$file" "$bakdir/" || log "backup failed: $file"
}

replace_if_smaller(){
  local orig="$1" cand="$2"
  [[ -f "$cand" ]] || return 1
  local old new saved
  old=$(filesize "$orig"); new=$(filesize "$cand")
  if (( new > 0 && new < old )); then
    if (( DRYRUN )); then
      log "[DRY] would replace $orig -> saved $((old-new)) bytes"
      rm -f -- "$cand" || :
      return 0
    fi
    mkbackup "$orig"
    mv -f -- "$cand" "$orig"
    log "Optimized: $orig (saved $((old-new)) bytes)"
    return 0
  fi
  rm -f -- "$cand" || :
  return 1
}

# ---- per-file optimizer (self-contained; exported for parallel) ----
optimize_file(){
  local file="$1" ext tmp tmp2
  ext="${file##*.}"; ext="${ext,,}"
  tmp="$(mktemp --suffix=".$ext")"
  trap 'rm -f -- "$tmp" "${tmp2:-}"' RETURN

  case "$ext" in
    png)
      cp -p -- "$file" "$tmp"
      has rimage && "${T[rimage]}" -i "$tmp" -o "${tmp}.r" &>/dev/null && mv -f "${tmp}.r" "$tmp" || :
      if (( LOSSY )) && has pngquant; then
        "${T[pngquant]}" --strip --quality=60-85 --speed=1 --output "$tmp" -- "$tmp" &>/dev/null || :
      fi
      has oxipng && "${T[oxipng]}" -o max --strip all -a -i 0 --force "$tmp" &>/dev/null || :
      has flaca && "${T[flaca]}" --no-symlinks --preserve-times "$tmp" &>/dev/null || :
      replace_if_smaller "$file" "$tmp"
      ;;
    jpg|jpeg)
      cp -p -- "$file" "$tmp"
      has rimage && "${T[rimage]}" -i "$tmp" -o "${tmp}.r" &>/dev/null && mv -f "${tmp}.r" "$tmp" || :
      has flaca && "${T[flaca]}" --no-symlinks --preserve-times "$tmp" &>/dev/null || :
      if has jpegoptim; then
        if (( LOSSY )); then
          "${T[jpegoptim]}" --strip-all --all-progressive --max=85 -- "$tmp" &>/dev/null || :
        else
          "${T[jpegoptim]}" --strip-all --all-progressive --preserve "$tmp" &>/dev/null || :
        fi
      fi
      replace_if_smaller "$file" "$tmp"
      ;;
    gif)
      cp -p -- "$file" "$tmp"
      if has gifsicle; then
        "${T[gifsicle]}" -O3 --batch "$tmp" &>/dev/null || :
      elif has gifski && has ffmpeg; then
        tmp2="$(mktemp --suffix=.gif)"; tmpdir="$(mktemp -d)"
        ffmpeg -i "$file" -hide_banner -loglevel error "$tmpdir/frame%06d.png" &>/dev/null || :
        gifski -o "$tmp2" "$tmpdir"/frame*.png &>/dev/null || :
        mv -f -- "$tmp2" "$tmp" 2>/dev/null || :
        rm -rf -- "$tmpdir" || :
      fi
      replace_if_smaller "$file" "$tmp"
      ;;
    svg)
      if has svgo; then
        "${T[svgo]}" --multipass --quiet -- "$file" -o "$tmp" &>/dev/null || :
        replace_if_smaller "$file" "$tmp"
      elif has scour; then
        "${T[scour]}" -i "$file" -o "$tmp" --enable-id-stripping --enable-comment-stripping &>/dev/null || :
        replace_if_smaller "$file" "$tmp"
      fi
      ;;
    webp)
      cp -p -- "$file" "$tmp"
      has rimage && "${T[rimage]}" -i "$tmp" -o "${tmp}.r" &>/dev/null && mv -f "${tmp}.r" "$tmp" || :
      if (( LOSSY )) && has cwebp && has ffmpeg; then
        tmp2="${tmp}.png"
        dwebp "$file" -o "$tmp2" &>/dev/null || :
        cwebp -q "$WEBP_QUALITY" "$tmp2" -o "$tmp" &>/dev/null || :
        rm -f -- "$tmp2" || :
      fi
      replace_if_smaller "$file" "$tmp"
      ;;
    avif)
      cp -p -- "$file" "$tmp"
      if has avifenc; then
        tmp2="${tmp}.out.avif"
        if (( LOSSY )); then
          "${T[avifenc]}" --min 20 --max "$AVIF_QUAL" --speed "$AVIF_SPEED" "$tmp" "$tmp2" &>/dev/null && mv -f "$tmp2" "$tmp" || :
        else
          "${T[avifenc]}" --min 0 --max 0 --speed "$AVIF_SPEED" "$tmp" "$tmp2" &>/dev/null && mv -f "$tmp2" "$tmp" || :
        fi
      fi
      replace_if_smaller "$file" "$tmp"
      ;;
    jxl)
      cp -p -- "$file" "$tmp"
      if has cjxl; then
        tmp2="${tmp}.out.jxl"
        "${T[cjxl]}" "$tmp" "$tmp2" --lossless_jpeg=1 &>/dev/null && mv -f "$tmp2" "$tmp" || :
      fi
      replace_if_smaller "$file" "$tmp"
      ;;
    html|htm)
      if has minify; then
        tmp2="${tmp}.min"
        "${T[minify]}" --type html "$file" > "$tmp2" 2>/dev/null && replace_if_smaller "$file" "$tmp2" || :
      fi
      ;;
    css)
      if has minify; then
        tmp2="${tmp}.min"
        "${T[minify]}" --type css "$file" > "$tmp2" 2>/dev/null && replace_if_smaller "$file" "$tmp2" || :
      fi
      ;;
    js)
      if has minify; then
        tmp2="${tmp}.min"
        "${T[minify]}" --type js "$file" > "$tmp2" 2>/dev/null && replace_if_smaller "$file" "$tmp2" || :
      fi
      ;;
    *)
      return 1
      ;;
  esac
}
export -f optimize_file replace_if_smaller filesize mkbackup
# ---- discovery ----
build_find_cmd(){
  local dir="$1"
  if has fd; then
    printf '%s\0' "$("$T[fd]" -t f -e png -e jpg -e jpeg -e gif -e svg -e webp -e avif -e jxl -e html -e htm -e css -e js . "$dir" 2>/dev/null)"
  else
    find "$dir" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.jxl' -o -iname '*.html' -o -iname '*.htm' -o -iname '*.css' -o -iname '*.js' \) -print0 2>/dev/null
  fi
}

# ---- parallel dispatch (rust-parallel -> parallel -> xargs) ----
dispatch_parallel(){
  local -a files=("${@}") runner
  [[ ${#files[@]} -gt 0 ]] || return 0
  # prefer rust-parallel if usable
  if [[ -n "${T[rustp]}" && "${T[rustp]}" != "true" && -x "${T[rustp]}" ]]; then
    # rust-parallel -s reads lines of shell commands
    local cmds_file; cmds_file="$(mktemp)"
    for f in "${files[@]}"; do printf '%s\n' "bash -c 'optimize_file \"$(printf "%q" "$f")\"'" >>"$cmds_file"; done
    "${T[rustp]}" -s --jobs "$JOBS" <"$cmds_file"
    rm -f -- "$cmds_file"
    return 0
  fi
  if [[ -n "${T[parallel]}" && "${T[parallel]}" != "true" ]]; then
    printf '%s\0' "${files[@]}" | "${T[parallel]}" -0 -j "$JOBS" bash -c 'optimize_file "$@"' _ {}
    return 0
  fi
  # fallback xargs
  printf '%s\0' "${files[@]}" | "${T[xargs]}" -0 -P "$JOBS" -I {} bash -c 'optimize_file "$@"' _ {}
}

# ---- TUI using sk (skim) or fzf; preview uses eza if available ----
tui_select_and_run(){
  local dir="$1" preview_cmd selected
  preview_cmd='echo {} | xargs -I{} '"${T[eza]##*/}"' -lh {} 2>/dev/null'
  mapfile -t selected < <(build_find_list "$dir" | "${T[sk]##*/}" --multi --height=80% --layout=reverse --prompt="Select files > " --preview="$preview_cmd" --read0 | tr '\0' '\n')
  (( ${#selected[@]} )) || { echo "No selection."; return; }
  dispatch_parallel "${selected[@]}"
}

# helper produces NUL-separated list to stdout for sk/fzf usage
build_find_list(){
  local dir=${1:-.}
  if has fd; then
    "$T[fd]" -0 -t f -e png -e jpg -e jpeg -e gif -e svg -e webp -e avif -e jxl -e html -e htm -e css -e js . "$dir"
  else
    find "$dir" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.jxl' -o -iname '*.html' -o -iname '*.htm' -o -iname '*.css' -o -iname '*.js' \) -print0
  fi
}

# ---- CLI parse ----
usage(){
  cat <<EOF
Usage: ${0##*/} [opts] [target]
  -h        help
  -t        launch TUI (sk/fzf) for interactive selection
  -j N      parallel jobs (default: auto)
  -l        enable lossy conversions
  -n        dry-run (no write)
  -b        keep backups (default)
  -B        disable backups
  -r        recursive (default non-recursive when using fd; flag kept for parity)
  -p        replace originals (remove originals when converted)
  -q N      webp quality (default: $WEBP_QUALITY)
EOF
  exit 0
}

# parse
while getopts ":htj:lnbBrpq:" opt; do
  case "$opt" in
    h) usage ;;
    t) TUI=1 ;;
    j) JOBS="$OPTARG" ;;
    l) LOSSY=1 ;;
    n) DRYRUN=1 ;;
    b) KEEP_BACKUPS=1 ;;
    B) KEEP_BACKUPS=0 ;;
    r) RECURSIVE=1 ;;
    p) REPLACE_ORIG=1 ;;
    q) WEBP_QUALITY="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))
[[ $# -ge 1 ]] && TARGET_DIR="$1"

# ---- sanity checks / info ----
log "Media optimizer starting. Target: $TARGET_DIR Jobs: $JOBS Lossy: $LOSSY Dry-run: $DRYRUN Backups: $KEEP_BACKUPS"
if (( DRYRUN )); then log "DRY RUN enabled — no files will be modified"; fi

# ---- run ----
if [[ "${TUI:-}" == "1" ]]; then
  if [[ -z "${T[sk]}" || "${T[sk]}" == "true" ]]; then
    die "No sk/fzf available for TUI"
  fi
  tui_select_and_run "$TARGET_DIR"
  exit 0
fi

# collect files into array
mapfile -d '' -t FILES < <(build_find_cmd "$TARGET_DIR")
if [[ ${#FILES[@]} -eq 0 ]]; then
  log "No media files found in $TARGET_DIR"
  exit 0
fi

# dispatch
dispatch_parallel "${FILES[@]}"

log "Done. See log at $LOGFILE (if any)."
exit 0
