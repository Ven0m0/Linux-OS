#!/usr/bin/env bash
#
# Title:         Media Optimizer TUI
# Description:   An interactive fzf-based TUI to losslessly or lossily
#                optimize images, SVGs, and web files in parallel.
#
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C

# --- Configuration & Globals ---
JOBS=$(nproc 2>/dev/null || echo 4)
LOSSY=0
KEEP_BACKUPS=1
TARGET_DIR="${1:-.}"

# TUI Colors
C_RED='\033[0;31m' C_GREEN='\033[0;32m' C_YELLOW='\033[1;33m' C_BLUE='\033[0;34m' C_NC='\033[0m'

# Check core dependency: fzf
if ! command -v fzf &>/dev/null; then
  printf "${C_RED}Error: fzf is not installed. It is required for the TUI.${C_NC}\n" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
LOG_FILE="$TMP_DIR/optimization_log.txt"
OPTIMIZER_SCRIPT="$TMP_DIR/optimize_one.sh"

# --- Cleanup ---
# Ensures temporary files are removed on any script exit.
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT SIGINT SIGTERM

# --- Logging ---
log_info() {
  printf '[%s] %s\n' "$(date +'%F %T')" "$1" >>"$LOG_FILE"
}

# --- Core Optimizer Logic ---
# This function creates a self-contained script that will be run in parallel for each file.
# It contains all the tool logic synthesized from your examples.
create_optimizer_script() {
cat > "$OPTIMIZER_SCRIPT" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
# --- Arguments ---
file="$1"
lossy_flag="$2"
keep_backups="$3"

# --- Helpers ---
filesize() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0; }
has() { command -v "$1" &>/dev/null; }

# Replaces the original file if the candidate is smaller.
replace_if_smaller() {
  local orig="$1" candidate="$2"
  [[ -f "$candidate" ]] || return 1
  local old_size; old_size=$(filesize "$orig")
  local new_size; new_size=$(filesize "$candidate")

  if (( new_size > 0 && new_size < old_size )); then
    if [[ "$keep_backups" -eq 1 ]]; then
      local backup_dir; backup_dir="$(dirname -- "$orig")/.backups"
      mkdir -p "$backup_dir"
      cp -a -- "$orig" "$backup_dir/"
    fi
    mv -f -- "$candidate" "$orig"
    printf "Optimized: %s (saved %s bytes)\n" "$orig" "$((old_size - new_size))"
    return 0
  else
    rm -f -- "$candidate"
    return 1
  fi
}

# --- Main Logic ---
ext_lower="$(tr '[:upper:]' '[:lower:]' <<< "${file##*.}")"
tmpf="$(mktemp "${file}.XXXXXX")"
# Always clean up the temp file
trap 'rm -f "$tmpf"' EXIT

case "$ext_lower" in
  png)
    cp -a -- "$file" "$tmpf" # Start with a copy
    # 1. Lossy compression with pngquant if enabled
    if [ "$lossy_flag" -eq 1 ] && has pngquant; then
      pngquant --quality=65-85 --speed=1 --strip --force --output "$tmpf" -- "$tmpf" &>/dev/null || :
    fi
    # 2. Lossless optimization with oxipng
    if has oxipng; then
      oxipng -o 4 --strip safe --alpha --force --out "$tmpf" "$tmpf" &>/dev/null || :
    fi
    # 3. Aggressive lossless with flaca if available
    if has flaca; then
      flaca --no-symlinks --preserve-times "$tmpf" &>/dev/null || :
    fi
    replace_if_smaller "$file" "$tmpf"
    ;;

  jpg|jpeg)
    cp -a -- "$file" "$tmpf" # Start with a copy
    # 1. Aggressive lossless with flaca
    if has flaca; then
      flaca --no-symlinks --preserve-times "$tmpf" &>/dev/null || :
    fi
    # 2. Standard optimization with jpegoptim
    if has jpegoptim; then
      if [ "$lossy_flag" -eq 1 ]; then
        jpegoptim --strip-all --all-progressive --max=85 -o -- "$tmpf" &>/dev/null || :
      else
        jpegoptim --strip-all --all-progressive --force -- "$tmpf" &>/dev/null || :
      fi
    fi
    replace_if_smaller "$file" "$tmpf"
    ;;

  gif)
    if has gifsicle; then
      # Gifsicle works in-place, so we operate on a temp copy
      cp -a -- "$file" "$tmpf"
      gifsicle -O3 --batch "$tmpf" &>/dev/null || :
      replace_if_smaller "$file" "$tmpf"
    fi
    ;;

  svg)
    if has scour; then
      scour -i "$file" -o "$tmpf" --enable-viewboxing --remove-metadata &>/dev/null || :
      replace_if_smaller "$file" "$tmpf"
    elif has svgo; then
      svgo "$file" -o "$tmpf" &>/dev/null || :
      replace_if_smaller "$file" "$tmpf"
    fi
    ;;

  webp|avif|jxl)
    # Re-encoding is always lossy, so only run in lossy mode
    if [ "$lossy_flag" -eq 1 ]; then
      case "$ext_lower" in
        webp)
          if has dwebp && has cwebp; then
            dwebp "$file" -o "$tmpf.png" &>/dev/null && \
            cwebp -q 80 "$tmpf.png" -o "$tmpf" &>/dev/null
            rm -f "$tmpf.png"
            replace_if_smaller "$file" "$tmpf"
          fi
          ;;
        avif)
          has avifenc && avifenc --min 30 --max 45 --speed 6 -o "$tmpf" "$file" &>/dev/null && replace_if_smaller "$file" "$tmpf"
          ;;
        jxl)
          has cjxl && cjxl "$file" "$tmpf" -d 1 &>/dev/null && replace_if_smaller "$file" "$tmpf"
          ;;
      esac
    fi
    ;;

  html|htm)
    if has minify; then
      minify --type html "$file" > "$tmpf" 2>/dev/null && replace_if_smaller "$file" "$tmpf"
    elif has html-minifier; then
      html-minifier --collapse-whitespace "$file" -o "$tmpf" 2>/dev/null && replace_if_smaller "$file" "$tmpf"
    fi
    ;;
esac
BASH
chmod +x "$OPTIMIZER_SCRIPT"
}

# --- File Discovery & Execution ---

# Uses fd (preferred) or find to discover optimizable files.
discover_files() {
  local dir="$1"
  local find_cmd
  if command -v fd &>/dev/null; then
    find_cmd=(fd --type f --no-ignore --hidden --extension png --extension jpg --extension jpeg --extension gif --extension svg --extension webp --extension avif --extension jxl --extension html --extension htm . "$dir")
  elif command -v fdfind &>/dev/null; then
    find_cmd=(fdfind --type f --no-ignore --hidden --extension png --extension jpg --extension jpeg --extension gif --extension svg --extension webp --extension avif --extension jxl --extension html --extension htm . "$dir")
  else
    find_cmd=(find "$dir" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.jxl' -o -iname '*.html' -o -iname '*.htm' \))
  fi
  # Exclude backup directories from the search
  "${find_cmd[@]}" | grep -v '/\.backups/'
}

# Runs the optimizer script on a list of files using the best parallel tool available.
run_parallel_optimization() {
  local -n files_ref=$1 # Pass file array by reference

  # Check which parallel runner to use
  local runner=""
  if command -v rust-parallel &>/dev/null; then runner="rust-parallel";
  elif command -v parallel &>/dev/null; then runner="gnu-parallel";
  else runner="xargs"; fi
  log_info "Using parallel runner: $runner with $JOBS jobs."
  printf "\n${C_BLUE}🚀 Starting optimization with ${C_YELLOW}$runner${C_NC} on ${C_YELLOW}${!#files_ref[*]}${C_NC} files...${C_NC}\n\n"

  # Execute based on the detected runner
  case "$runner" in
    "rust-parallel")
      printf '%s\0' "${files_ref[@]}" | rust-parallel -0 -j "$JOBS" "$OPTIMIZER_SCRIPT" {} "$LOSSY" "$KEEP_BACKUPS"
      ;;
    "gnu-parallel")
      printf '%s\0' "${files_ref[@]}" | parallel -0 -j "$JOBS" "$OPTIMIZER_SCRIPT" {} "$LOSSY" "$KEEP_BACKUPS"
      ;;
    "xargs")
      printf '%s\0' "${files_ref[@]}" | xargs -0 -P "$JOBS" -I {} "$OPTIMIZER_SCRIPT" {} "$LOSSY" "$KEEP_BACKUPS"
      ;;
  esac
  printf "\n${C_GREEN}✅ Optimization complete.${C_NC}\n"
  printf "See log for details: ${C_YELLOW}$LOG_FILE${C_NC}\n"
}

# --- TUI Menus ---

# Main interactive workflow: select files, confirm action, and run.
select_files_and_run() {
  local files_to_process=()
  local header fzf_prompt
  header="[Tab] to select multiple files | [Enter] to proceed"
  fzf_prompt="🔎 Select files to optimize in '$TARGET_DIR' > "

  # Use fzf to let the user select files
  mapfile -t files_to_process < <(
    discover_files "$TARGET_DIR" | fzf --multi --height=80% --layout=reverse \
      --prompt="$fzf_prompt" --header="$header" \
      --preview='ls -lh {}' --preview-window='up:30%:wrap'
  )

  if (( ${#files_to_process[@]} == 0 )); then
    echo "No files selected."
    return
  fi

  # Confirm action with another fzf menu
  local action
  action=$(printf "🚀 Optimize %s Selected Files\n❌ Cancel" "${#files_to_process[@]}" | fzf --height=15% --layout=reverse --prompt="Confirm action > ")

  if [[ "$action" == "🚀"* ]]; then
    run_parallel_optimization files_to_process
  else
    echo "Operation cancelled."
  fi
  printf "\nPress [Enter] to return to the main menu..."
  read -r
}

# Settings menu to toggle options.
settings_menu() {
  while true; do
    local lossy_status="OFF" backup_status="ON"
    [[ "$LOSSY" -eq 1 ]] && lossy_status="ON"
    [[ "$KEEP_BACKUPS" -eq 1 ]] || backup_status="OFF"

    local choice
    choice=$(printf "Toggle Lossy Mode (Currently: ${C_YELLOW}%s${C_NC})\nToggle Backups (Currently: ${C_YELLOW}%s${C_NC})\nSet Parallel Jobs (Currently: ${C_YELLOW}%s${C_NC})\n🔙 Back to Main Menu" \
      "$lossy_status" "$backup_status" "$JOBS" | fzf --height=25% --layout=reverse --prompt="⚙️ Settings > ")

    case "$choice" in
      *"Toggle Lossy Mode"*) ((LOSSY = 1 - LOSSY)) ;;
      *"Toggle Backups"*) ((KEEP_BACKUPS = 1 - KEEP_BACKUPS)) ;;
      *"Set Parallel Jobs"*)
        printf "Enter number of parallel jobs (current: %s): " "$JOBS"
        read -r new_jobs
        if [[ "$new_jobs" =~ ^[0-9]+$ ]] && (( new_jobs > 0 )); then
          JOBS="$new_jobs"
        else
          echo "Invalid input. Please enter a positive number."
          sleep 1
        fi
        ;;
      *"Back to Main Menu"|*) return ;;
    esac
  done
}

# --- Main Program Loop ---

# Create the self-contained optimizer script on startup
create_optimizer_script

# Main TUI loop
while true; do
  clear
  printf "${C_BLUE}--- Media Optimizer TUI ---${C_NC}\n"
  printf "Target Directory: ${C_YELLOW}%s${C_NC}\n\n" "$TARGET_DIR"

  local choice
  choice=$(printf "▶️  Select Files & Optimize\n⚙️  Settings\n🚪 Quit" | fzf --height=20% --layout=reverse --prompt="Action > ")

  case "$choice" in
    *"Select Files"*) select_files_and_run ;;
    *"Settings"*) settings_menu ;;
    *"Quit"|*) break ;;
  esac
done

echo "Exiting."
