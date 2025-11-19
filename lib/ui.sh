#!/usr/bin/env bash
# Linux-OS UI Library
# User interface functions: banners, menus, progress indicators
# Requires: lib/base.sh
#
# This library provides:
# - Banner printing with gradient effects
# - Pre-defined ASCII art banners
# - Text processing utilities
# - Menu functions

[[ -z ${_BASE_LIB_LOADED:-} ]] && {
  echo "Error: lib/base.sh must be sourced before lib/ui.sh" >&2
  exit 1
}

# ============================================================================
# Banner Printing Functions
# ============================================================================

# Print banner with trans flag gradient
# Usage: print_banner "banner_text" [title]
print_banner() {
  local banner="$1" title="${2:-}"
  local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")

  # Optimized: Use read loop instead of mapfile to avoid subprocess
  local -a lines=()
  while IFS= read -r line || [[ -n $line ]]; do
    lines+=("$line")
  done <<<"$banner"

  local line_count=${#lines[@]} segments=${#flag_colors[@]}

  if ((line_count <= 1)); then
    printf '%s%s%s\n' "${flag_colors[0]}" "${lines[0]}" "$DEF"
  else
    for i in "${!lines[@]}"; do
      local segment_index=$((i * (segments - 1) / (line_count - 1)))
      ((segment_index >= segments)) && segment_index=$((segments - 1))
      printf '%s%s%s\n' "${flag_colors[segment_index]}" "${lines[i]}" "$DEF"
    done
  fi

  [[ -n $title ]] && xecho "$title"
}

# Display colorized banner with custom gradient
# Usage: display_banner "banner_text" [colors...]
# Example: display_banner "$banner" "$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU"
display_banner() {
  local banner_text="$1"
  shift
  local -a flag_colors=("$@")

  # Default to trans flag colors if none provided
  if ((${#flag_colors[@]} == 0)); then
    flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")
  fi

  mapfile -t banner_lines <<<"$banner_text"
  local lines=${#banner_lines[@]}
  local segments=${#flag_colors[@]}

  # Simple output if only one line
  if ((lines <= 1)); then
    for line in "${banner_lines[@]}"; do
      printf "%s%s%s\n" "${flag_colors[0]}" "$line" "$DEF"
    done
  else
    # Apply gradient across lines
    for i in "${!banner_lines[@]}"; do
      local segment_index=$((i * (segments - 1) / (lines - 1)))
      ((segment_index >= segments)) && segment_index=$((segments - 1))
      printf "%s%s%s\n" "${flag_colors[segment_index]}" "${banner_lines[i]}" "$DEF"
    done
  fi
}

# ============================================================================
# Pre-defined ASCII Art Banners
# ============================================================================

# Get UPDATE banner
get_update_banner() {
  cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
}

# Get CLEAN banner
get_clean_banner() {
  cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝
EOF
}

# Get SETUP banner
get_setup_banner() {
  cat <<'EOF'
███████╗███████╗████████╗██╗   ██╗██████╗
██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
███████╗█████╗     ██║   ██║   ██║██████╔╝
╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝
███████║███████╗   ██║   ╚██████╔╝██║
╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝
EOF
}

# Get FIX banner
get_fix_banner() {
  cat <<'EOF'
███████╗██╗██╗  ██╗
██╔════╝██║╚██╗██╔╝
█████╗  ██║ ╚███╔╝
██╔══╝  ██║ ██╔██╗
██║     ██║██╔╝ ██╗
╚═╝     ╚═╝╚═╝  ╚═╝
EOF
}

# Get OPTIMIZE banner
get_optimize_banner() {
  cat <<'EOF'
 ██████╗ ██████╗ ████████╗██╗███╗   ███╗██╗███████╗███████╗
██╔═══██╗██╔══██╗╚══██╔══╝██║████╗ ████║██║╚══███╔╝██╔════╝
██║   ██║██████╔╝   ██║   ██║██╔████╔██║██║  ███╔╝ █████╗
██║   ██║██╔═══╝    ██║   ██║██║╚██╔╝██║██║ ███╔╝  ██╔══╝
╚██████╔╝██║        ██║   ██║██║ ╚═╝ ██║██║███████╗███████╗
 ╚═════╝ ╚═╝        ╚═╝   ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝
EOF
}

# Print predefined banner by name
# Usage: print_named_banner "update"|"clean"|"setup"|"fix"|"optimize" [title]
print_named_banner() {
  local name="$1" title="${2:-Meow (> ^ <)}" banner

  case "$name" in
    update) banner=$(get_update_banner) ;;
    clean) banner=$(get_clean_banner) ;;
    setup) banner=$(get_setup_banner) ;;
    fix) banner=$(get_fix_banner) ;;
    optimize) banner=$(get_optimize_banner) ;;
    *) die "Unknown banner name: $name" ;;
  esac

  print_banner "$banner" "$title"
}

# ============================================================================
# Text Processing Utilities
# ============================================================================

# Remove comments from text
# Removes shell-style comments (# ...) and blank lines
# Usage: cat file | remove_comments
remove_comments() {
  sed -e 's/[[:blank:]]*#.*//;/^$/d'
}

# Remove duplicate lines while preserving order
# Usage: remove_duplicate_lines [file]
remove_duplicate_lines() {
  if [[ -n "${1:-}" && -f "$1" ]]; then
    awk '!seen[$0]++' "$1"
  else
    awk '!seen[$0]++'
  fi
}

# Remove duplicate lines and sort (faster for large files)
# Usage: remove_duplicate_lines_sorted [file]
remove_duplicate_lines_sorted() {
  if [[ -n "${1:-}" && -f "$1" ]]; then
    sort -u "$1"
  else
    sort -u
  fi
}

# Remove leading and trailing whitespace
# Usage: cat file | remove_trailing_spaces
remove_trailing_spaces() {
  awk '{gsub(/^ +| +$/,"")}1'
}

# Remove blank lines
# Usage: cat file | remove_blank_lines
remove_blank_lines() {
  sed '/^$/d'
}

# Convert to lowercase
# Usage: cat file | to_lowercase
to_lowercase() {
  tr '[:upper:]' '[:lower:]'
}

# Convert to uppercase
# Usage: cat file | to_uppercase
to_uppercase() {
  tr '[:lower:]' '[:upper:]'
}

# Remove ANSI color codes from text
# Usage: cat colored_output | remove_colors
remove_colors() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# Extract URLs from text
# Usage: cat file | extract_urls
extract_urls() {
  grep -oE '(https?|ftp)://[^[:space:]]+' "$@"
}

# Extract IP addresses from text
# Usage: cat file | extract_ips
extract_ips() {
  grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$@"
}

# Normalize whitespace (convert tabs to spaces, collapse multiple spaces)
# Usage: cat file | normalize_whitespace
normalize_whitespace() {
  sed -e 's/\t/ /g' -e 's/  */ /g'
}

# ============================================================================
# Progress Indicators
# ============================================================================

# Simple spinner
# Usage: show_spinner PID
show_spinner() {
  local pid=$1
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0

  while kill -0 "$pid" 2>/dev/null; do
    i=$(((i + 1) % 10))
    printf '\r%s ' "${spin:$i:1}"
    sleep 0.1
  done
  printf '\r'
}

# Progress bar
# Usage: progress_bar 50 100 "Processing"
progress_bar() {
  local current=$1 total=$2 message="${3:-}"
  local width=50
  local percentage=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))

  printf '\r%s [' "$message"
  printf '%*s' "$filled" | tr ' ' '='
  printf '%*s' "$empty" | tr ' ' ' '
  printf '] %d%%' "$percentage"

  [[ $current -eq $total ]] && printf '\n'
}

# ============================================================================
# Box Drawing
# ============================================================================

# Draw a box around text
# Usage: draw_box "Title" "Line 1" "Line 2" ...
draw_box() {
  local -a lines=("$@")
  local max_len=0 line

  # Find maximum line length
  for line in "${lines[@]}"; do
    ((${#line} > max_len)) && max_len=${#line}
  done

  # Top border
  printf '┌%*s┐\n' $((max_len + 2)) | tr ' ' '─'

  # Content lines
  for line in "${lines[@]}"; do
    printf '│ %-*s │\n' "$max_len" "$line"
  done

  # Bottom border
  printf '└%*s┘\n' $((max_len + 2)) | tr ' ' '─'
}

# ============================================================================
# Simple Menu System
# ============================================================================

# Display a simple menu and get user choice
# Usage: choice=$(show_menu "Option 1" "Option 2" "Option 3")
show_menu() {
  local -a options=("$@")
  local i choice

  for i in "${!options[@]}"; do
    printf '%d) %s\n' "$((i + 1))" "${options[$i]}"
  done

  printf '\nSelect an option [1-%d]: ' "${#options[@]}"
  read -r choice

  if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
    printf '%d\n' "$((choice - 1))"
    return 0
  else
    return 1
  fi
}

# ============================================================================
# Library Load Confirmation
# ============================================================================

_UI_LIB_LOADED=1
return 0
