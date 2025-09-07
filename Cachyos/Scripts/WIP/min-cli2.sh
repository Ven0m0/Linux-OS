#!/usr/bin/env bash
# optimize-media.sh
# Optimize image and web files in a directory or single file.
# - Accepts optional directory or file argument (defaults to cwd)
# - Uses fd/fdfind or find for discovery
# - Applies tools (rimage, flaca, rust-parallel/GNU parallel/xargs concurrency,
#   cwebp, avifenc, jpegxl/cjxl, jpegoptim, oxipng, pngquant, gifsicle,
#   scour/svgo, minhtml)
# - Does NOT overwrite originals directly. Creates backups.
# - Robust checks for tool availability and logs all operations & errors.
# - Parallelizes work; tries to use rust-parallel if installed, else falls back.
#
# Usage:
#   ./optimize-media.sh [path]
# Example:
#   ./optimize-media.sh /path/to/images
#
set -euo pipefail
IFS=$'\n\t'

### Configuration (tweak these)
JOBS="$(nproc 2>/dev/null || echo 4)"     # concurrency
PNGQUANT_QUALITY="60-80"                 # pngquant quality (lossy). Adjust if you want narrower range.
AVIF_QUALITY="35"                        # avifenc quality (lower = smaller file)
CWEBP_QUALITY="85"                       # cwebp quality (0-100)
JPEGL_QUALITY="85"                       # jpeg encoder quality if used
BACKUPS_SUBDIR=".imgopt_backups"         # backups directory placed in each target dir
LOGFILE="$(mktemp "/tmp/imgopt_log.XXXXXX")"
TMPROOT="$(mktemp -d "/tmp/imgopt_tmp.XXXXXX")"
# Ensure cleanup on exit
cleanup() {
  rm -rf "$TMPROOT" || true
}
trap cleanup EXIT

echo "Log: $LOGFILE"
echo "Temp dir: $TMPROOT"
echo "Start: $(date --iso-8601=seconds)" >>"$LOGFILE"

### Helper utilities
log_info()  { printf '%s [%s] %s\n' "$(date --iso-8601=seconds)" "INFO" "$*" | tee -a "$LOGFILE"; }
log_warn()  { printf '%s [%s] %s\n' "$(date --iso-8601=seconds)" "WARN" "$*" | tee -a "$LOGFILE" >&2; }
log_error() { printf '%s [%s] %s\n' "$(date --iso-8601=seconds)" "ERROR" "$*" | tee -a "$LOGFILE" >&2; }

die() {
  log_error "$*"
  exit 1
}

### Input parsing
TARGET="${1-.}"
if [ ! -e "$TARGET" ]; then
  die "Target path does not exist: $TARGET"
fi

# If target is single file, we'll just operate on that file
if [ -f "$TARGET" ]; then
  SINGLE_FILE="$(realpath "$TARGET")"
  SEARCH_DIR=""
else
  SEARCH_DIR="$(realpath "$TARGET")"
  SINGLE_FILE=""
fi

### Discovery command (fd/fdfind preferred, fall back to find)
FIND_CMD=""
if command -v fd >/dev/null 2>&1; then
  FIND_CMD="fd"
elif command -v fdfind >/dev/null 2>&1; then
  FIND_CMD="fdfind"
else
  FIND_CMD="find"
fi
log_info "Using file discovery: $FIND_CMD"

# Build list of files to process (absolute paths)
mapfile -t FILES < <(
  if [ -n "$SINGLE_FILE" ]; then
    printf '%s\n' "$SINGLE_FILE"
  else
    if [ "$FIND_CMD" = "fd" ] || [ "$FIND_CMD" = "fdfind" ]; then
      # fd: supply an empty pattern (.) and explicit extensions. -0 not needed since we read lines into array
      "$FIND_CMD" -t f -e webp -e avif -e jpeg -e jpg -e png -e gif -e svg -e html --hidden --follow -x printf '%p\n' . "$SEARCH_DIR"
    else
      # find fallback with case-insensitive matching
      find "$SEARCH_DIR" -type f \( -iname '*.webp' -o -iname '*.avif' -o -iname '*.jpeg' -o -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.html' \) -print
    fi
  fi
)

if [ "${#FILES[@]}" -eq 0 ]; then
  log_info "No matching files found in target."
  exit 0
fi

log_info "Discovered ${#FILES[@]} files to consider."

### Tool detection helpers
have() {
  command -v "$1" >/dev/null 2>&1
}

# Detect some alternative command names for certain tools
JPEGXL_CMD=""
for c in cjxl jpegxl jxl; do
  if have "$c"; then
    JPEGXL_CMD="$c"
    break
  fi
done

SVG_OPT_CMD=""
if have scour; then
  SVG_OPT_CMD="scour"
elif have svgo; then
  SVG_OPT_CMD="svgo"
fi

MINHTML_CMD=""
if have minhtml; then
  MINHTML_CMD="minhtml"
elif have minify; then
  MINHTML_CMD="minify"
fi

PARALLEL_TOOL="none"
# Prefer rust-parallel if present (attempt to use it in a GNU-parallel-like way; fallback safe methods below)
if have rust-parallel; then
  PARALLEL_TOOL="rust-parallel"
elif have parallel; then
  PARALLEL_TOOL="gnu-parallel"
elif have xargs; then
  PARALLEL_TOOL="xargs"
else
  PARALLEL_TOOL="internal"
fi
log_info "Parallel strategy: $PARALLEL_TOOL (JOBS=$JOBS)"

### Prepare backups directory root (we create per-file backups where originals live)
# Function to ensure backups directory exists in same dir as file
ensure_backups_dir() {
  local file="$1"
  local d
  d="$(dirname -- "$file")"
  mkdir -p "$d/$BACKUPS_SUBDIR"
  echo "$d/$BACKUPS_SUBDIR"
}

### Core per-file optimization function
# Note: This function writes to stdout/stderr only for progress; main logging goes to the log file.
optimize_one_file() {
  local file="$1"
  # Safeguard: don't process files inside backups directory to avoid recursive processing
  case "$file" in
    *"/$BACKUPS_SUBDIR/"* )
      echo "SKIP_BACKUP_FILE $file" >>"$LOGFILE"
      return 0
      ;;
  esac

  log_info "Processing: $file"
  local orig_size new_size
  orig_size=$(stat -c%s -- "$file" 2>/dev/null || echo 0)

  local ext="${file##*.}"
  ext="${ext,,}"  # lowercase

  local workdir
  workdir="$(mktemp -d "$TMPROOT/work.XXXX")"
  local workfile="$workdir/current"
  cp -- "$file" "$workfile"

  local tool_ok=false
  local step_status
  # Helper to try a command that produces "$workdir/next" from "$workfile"
  try_tool() {
    local cmd_desc="$1"; shift
    log_info "[$file] -> $cmd_desc"
    # run provided command(s) in a subshell so we can handle output/exit status
    # The command implementations should write output to "$workdir/next"
    if bash -c "$*" >/dev/null 2>>"$LOGFILE"; then
      if [ -s "$workdir/next" ]; then
        mv -f "$workdir/next" "$workfile"
        tool_ok=true
        step_status=0
      else
        # some tools may write in-place; in that case we assume success if exit=0
        step_status=0
      fi
      return 0
    else
      step_status=$?
      log_warn "Tool failed for $file: $cmd_desc (exit $step_status)"
      return $step_status
    fi
  }

  # ---------------------------
  # 1) rimage (general image processing)
  # rimage can be used for some formats to recompress/strip metadata.
  # If rimage exists, run it and write result to workdir/next (if it writes to file)
  # Typical usage: rimage -i input -o output (but implementations vary).
  # We'll try a few common invocation patterns, but gracefully skip on failure.
  # ---------------------------
  if have rimage; then
    # Attempt rimage with common flags. We will try two invocation styles.
    # First try: rimage -i in -o out
    if try_tool "rimage (style: -i -o)" 'rimage -i "$workfile" -o "$workdir/next"'; then
      :
    else
      # try: rimage "$workfile" -o "$workdir/next"
      try_tool "rimage (style: infile -o outfile)" 'rimage "$workfile" -o "$workdir/next"' || true
    fi
  else
    echo "rimage not found; skipping" >>"$LOGFILE"
  fi

  # ---------------------------
  # 2) flaca (further optimization)
  # flaca typically operates in-place or outputs to a specified file.
  # Try common invocation: flaca -o out in
  # ---------------------------
  if have flaca; then
    try_tool "flaca (optimize)" 'flaca -o "$workdir/next" "$workfile" || flaca "$workfile" -o "$workdir/next"' || true
  else
    echo "flaca not found; skipping" >>"$LOGFILE"
  fi

  # ---------------------------
  # Now use format-specific tools in the requested order.
  # All tools should produce $workdir/next when possible; otherwise we accept exit=0 in-place.
  # ---------------------------
  case "$ext" in
    webp)
      # Re-encode / recompress using cwebp
      if have cwebp; then
        # Lossy re-encode with given quality
        # Keep metadata stripped for smaller size via -metadata none
        try_tool "cwebp (recompress, quality=$CWEBP_QUALITY)" 'cwebp -q '"$CWEBP_QUALITY"' -metadata none "$workfile" -o "$workdir/next"' || true
      else
        echo "cwebp not found; skipping webp re-encode" >>"$LOGFILE"
      fi
      ;;
    avif)
      if have avifenc; then
        # avifenc usage: avifenc [options] input output
        try_tool "avifenc (quality=$AVIF_QUALITY)" 'avifenc --min '"$AVIF_QUALITY"' --max '"$AVIF_QUALITY"' --speed 4 --progressive --quiet "$workfile" "$workdir/next"' || \
        try_tool "avifenc (fallback simple)" 'avifenc -q '"$AVIF_QUALITY"' "$workfile" "$workdir/next"' || true
      else
        echo "avifenc not found; skipping avif recompression" >>"$LOGFILE"
      fi
      ;;
    jpeg|jpg)
      # For JPEG, we run jpegxl (if available), then jpegoptim
      if [ -n "$JPEGXL_CMD" ]; then
        # cjxl typically encodes to JXL, but user requested jpegxl tool - some setups provide jpegxl encoders.
        # We'll attempt an in-place recompress path where possible; otherwise skip.
        # Example for cjxl: cjxl in.jpg out.jxl -q 95
        TMP_OUT="$workdir/next"
        if [ "$JPEGXL_CMD" = "cjxl" ]; then
          # Re-encode to JXL container, but since original is JPEG we might not want to convert format.
          # We will skip actually converting to JXL unless user wants that. Instead, if cjxl supports recompressing JPEG in-place it's uncommon.
          echo "cjxl exists but conversion to JXL is format-changing; skipping automatic conversion to .jxl unless desired." >>"$LOGFILE"
        else
          # Unknown jpegxl binary name; attempt safe invocation
          try_tool "jpegxl (safe attempt)" "$JPEGXL_CMD \"$workfile\" \"$workdir/next\" -q $JPEGL_QUALITY" || true
        fi
      else
        echo "jpegxl not found; skipping jpegxl step" >>"$LOGFILE"
      fi

      if have jpegoptim; then
        # jpegoptim typical usage: jpegoptim --strip-all --all-progressive -m85 -o output? jpegoptim works in-place; we'll run on a copy
        # Create a temporary copy to run jpegoptim in-place, then move it to next path
        cp -- "$workfile" "$workdir/jpegoptim_in.jpg"
        if jpegoptim --strip-all --all-progressive --max="$JPEGL_QUALITY" "$workdir/jpegoptim_in.jpg" >>"$LOGFILE" 2>&1; then
          mv -f "$workdir/jpegoptim_in.jpg" "$workdir/next"
          rm -f "$workdir/jpegoptim_in.jpg" || true
          tool_ok=true
        else
          rm -f "$workdir/jpegoptim_in.jpg" || true
          log_warn "jpegoptim failed for $file"
        fi
      else
        echo "jpegoptim not found; skipping jpegoptim" >>"$LOGFILE"
      fi
      ;;
    png)
      # PNG pipeline: oxipng (lossless), then pngquant (lossy) optionally
      if have oxipng; then
        # oxipng: oxipng -o <level> -strip all -out out.png in.png
        try_tool "oxipng (lossless, level 4)" 'oxipng -o 4 --strip all -q -o "$workdir/next" "$workfile"' || true
      else
        echo "oxipng not found; skipping oxipng" >>"$LOGFILE"
      fi

      if have pngquant; then
        # pngquant produces a new file; use --quality and --skip-if-larger and write to next
        # Use --force to override if-necessary; we rely on --skip-if-larger to not worsen size
        try_tool "pngquant (quality=$PNGQUANT_QUALITY, lossy)" 'pngquant --quality '"$PNGQUANT_QUALITY"' --skip-if-larger --output "$workdir/next" -- "$workfile"' || true
      else
        echo "pngquant not found; skipping pngquant" >>"$LOGFILE"
      fi
      ;;
    gif)
      if have gifsicle; then
        # gifsicle: optimize with level 3
        try_tool "gifsicle (-O3)" 'gifsicle -O3 "$workfile" -o "$workdir/next"' || true
      else
        echo "gifsicle not found; skipping gif optimization" >>"$LOGFILE"
      fi
      ;;
    svg)
      if [ -n "$SVG_OPT_CMD" ]; then
        if [ "$SVG_OPT_CMD" = "scour" ]; then
          # scour in: scour -i in.svg -o out.svg --remove-metadata --enable-viewboxing
          try_tool "scour (SVG)" 'scour -i "$workfile" -o "$workdir/next" --remove-metadata --enable-viewboxing --enable-id-stripping --shorten-ids' || true
        else
          # svgo: svgo --input in.svg --output out.svg
          try_tool "svgo (SVG)" 'svgo "$workfile" -o "$workdir/next"' || true
        fi
      else
        echo "No SVG optimizer (scour or svgo) found; skipping SVG optimization" >>"$LOGFILE"
      fi
      ;;
    html)
      if [ -n "$MINHTML_CMD" ]; then
        # minhtml or minify: try both invocation variants
        if [ "$MINHTML_CMD" = "minhtml" ]; then
          try_tool "minhtml (HTML)" 'minhtml "$workfile" > "$workdir/next"' || true
        else
          # minify typically supports -o out in
          try_tool "minify (HTML)" 'minify --type html "$workfile" > "$workdir/next"' || true
        fi
      else
        echo "No HTML minifier (minhtml/minify) found; skipping HTML minification" >>"$LOGFILE"
      fi
      ;;
    *)
      echo "Unknown extension: $ext; skipping format-specific tools for $file" >>"$LOGFILE"
      ;;
  esac

  # After attempting tools, decide if we should replace original
  if [ -f "$workfile" ]; then
    new_size=$(stat -c%s -- "$workfile" 2>/dev/null || echo 0)
  else
    new_size=0
  fi

  # If any tool produced a different file and it's smaller, replace original with backup
  if [ "$new_size" -gt 0 ] && [ "$new_size" -lt "$orig_size" ]; then
    # create backup alongside original
    local bdir
    bdir="$(ensure_backups_dir "$file")"
    local bname
    bname="$(basename -- "$file").$(date +%Y%m%dT%H%M%S).bak"
    if mv -- "$file" "$bdir/$bname"; then
      if mv -f "$workfile" "$file"; then
        log_info "Replaced $file (orig: $orig_size -> new: $new_size). Backup: $bdir/$bname"
        echo "$file | OK | $orig_size -> $new_size | backup: $bdir/$bname" >>"$LOGFILE"
      else
        # restore from backup if replacement failed
        mv -f "$bdir/$bname" "$file" || log_warn "Failed to restore $file after failed replace"
        log_error "Failed to move optimized file into place for $file"
      fi
    else
      log_error "Failed to create backup for $file; skipping replacement"
    fi
  else
    # no improvement or no new file - keep original
    if [ "$new_size" -eq "$orig_size" ]; then
      log_info "No size improvement for $file (size unchanged: $orig_size). Keeping original."
      echo "$file | NO_CHANGE | $orig_size" >>"$LOGFILE"
    else
      log_info "Optimization did not produce smaller file for $file (orig: $orig_size, new: $new_size). Keeping original."
      echo "$file | SKIPPED_OR_WORSE | $orig_size -> $new_size" >>"$LOGFILE"
    fi
  fi

  # cleanup per-file workdir
  rm -rf -- "$workdir" || true
  return 0
}

export -f optimize_one_file
export LOGFILE TMPROOT BACKUPS_SUBDIR PNGQUANT_QUALITY AVIF_QUALITY CWEBP_QUALITY JPEGL_QUALITY

### Create a small wrapper script to call optimize_one_file for a path (used by external parallelers)
WRAPPER_SCRIPT="$TMPROOT/opt_wrapper.sh"
cat > "$WRAPPER_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
file="$1"
# The parent script exported optimize_one_file via environment? If not available, source self (not possible).
# We'll call the parent script recursively with a special mode to process a single file.
# Parent script path:
PARENT_SCRIPT="${OPT_PARENT_SCRIPT:-}"
if [ -z "$PARENT_SCRIPT" ] || [ ! -x "$PARENT_SCRIPT" ]; then
  echo "Parent script not available in wrapper" >&2
  exit 2
fi
# call parent script with an internal mode
"$PARENT_SCRIPT" --run-single "$file"
EOF
chmod +x "$WRAPPER_SCRIPT"

# If script is invoked with --run-single, call optimize_one_file directly.
if [ "${1-}" = "--run-single" ]; then
  if [ "${2-}" = "" ]; then
    die "Missing file for --run-single"
  fi
  optimize_one_file "$2"
  exit 0
fi

# Make sure wrapper knows parent script path
export OPT_PARENT_SCRIPT="$(realpath "$0")"

### Parallel execution:
# If rust-parallel is present we attempt to use it in a GNU-parallel-like manner,
# but we will gracefully fallback to other methods if it fails.
run_parallel_jobs() {
  local -n arr=$1
  local total=${#arr[@]}
  log_info "Launching $total tasks with strategy: $PARALLEL_TOOL"
  case "$PARALLEL_TOOL" in
    rust-parallel)
      # Try to use rust-parallel like: rust-parallel -j N -- wrapper.sh {}
      if rust-parallel --version >/dev/null 2>&1; then
        # Attempt invocation; if it fails, fallback
        if printf '%s\n' "${arr[@]}" | rust-parallel -j "$JOBS" -- "$WRAPPER_SCRIPT" {}; then
          return 0
        else
          log_warn "rust-parallel invocation failed; falling back"
        fi
      else
        log_warn "rust-parallel exists but --version check failed; falling back"
      fi
      ;;
    gnu-parallel)
      # parallel -j N wrapper ::: files...
      if printf '%s\n' "${arr[@]}" | parallel -j "$JOBS" -- "$WRAPPER_SCRIPT" {}; then
        return 0
      else
        log_warn "gnu parallel invocation failed; falling back"
      fi
      ;;
    xargs)
      # xargs -0 -n1 -P jobs wrapper
      # Use null-delimited safe transmission
      printf '%s\0' "${arr[@]}" | xargs -0 -n1 -P "$JOBS" "$WRAPPER_SCRIPT"
      return 0
      ;;
    internal)
      # Internal job pool (Bash). Start up to $JOBS background jobs.
      local i=0
      local pids=()
      for f in "${arr[@]}"; do
        ( "$0" --run-single "$f" ) &
        pids+=($!)
        i=$((i+1))
        # If running jobs reach limit, wait for any to finish
        while [ "$(jobs -pr | wc -l)" -ge "$JOBS" ]; do
          sleep 0.1
        done
      done
      # wait for all pids
      for pid in "${pids[@]}"; do
        wait "$pid" || true
      done
      return 0
      ;;
    *)
      # fallback to xargs-like
      printf '%s\0' "${arr[@]}" | xargs -0 -n1 -P "$JOBS" "$WRAPPER_SCRIPT"
      return 0
      ;;
  esac

  # If we get here, previous attempts failed; fallback to internal method
  log_info "Falling back to internal runner"
  PARALLEL_TOOL="internal"
  run_parallel_jobs arr
}

# Run the parallel jobs on FILES
run_parallel_jobs FILES

### Summary
echo "----- SUMMARY -----" | tee -a "$LOGFILE"
total_files=${#FILES[@]}
optimized_count=$(grep -c ' \| OK \| ' "$LOGFILE" || true)
# Count lines that show OK entries
ok_count=$(grep -cE " \| OK \|" "$LOGFILE" || true)
nochange_count=$(grep -cE " \| NO_CHANGE \|" "$LOGFILE" || true)
skipped_count=$(grep -cE " \| SKIPPED_OR_WORSE \|" "$LOGFILE" || true)
errors_count=$(grep -cE "ERROR" "$LOGFILE" || true)

echo "Total files considered: $total_files" | tee -a "$LOGFILE"
echo "Successful replacements (smaller and replaced): $ok_count" | tee -a "$LOGFILE"
echo "No-change (kept original): $nochange_count" | tee -a "$LOGFILE"
echo "Skipped or worse (kept original): $skipped_count" | tee -a "$LOGFILE"
echo "Logged errors/warnings: $errors_count" | tee -a "$LOGFILE"
echo "Detailed log file: $LOGFILE"
echo "Backups stored next to originals in subdirectory: $BACKUPS_SUBDIR"
echo "Done: $(date --iso-8601=seconds)" >>"$LOGFILE"
