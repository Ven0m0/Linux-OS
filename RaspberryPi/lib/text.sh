#!/usr/bin/env bash
# Text processing utilities library
# Contains shared functions for text manipulation and file processing

# Color constants for terminal output
# Standard ANSI colors
export BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
export BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
# Extended colors (256-color palette)
export LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
# Text effects
export DEF=$'\e[0m' BLD=$'\e[1m'

# Remove comments from text
# Removes shell-style comments (# ...) and blank lines
# Usage: cat file | remove_comments
# Or: remove_comments < file
remove_comments() {
  sed -e 's/[[:blank:]]*#.*//;/^$/d'
}

# Alternative name for compatibility
removeComments() {
  remove_comments
}

# Remove duplicate lines while preserving order
# Usage: remove_duplicate_lines file
# Or: cat file | remove_duplicate_lines
remove_duplicate_lines() {
  if [[ -n "${1:-}" && -f "$1" ]]; then
    awk '!seen[$0]++' "$1"
  else
    awk '!seen[$0]++'
  fi
}

# Remove duplicate lines and sort (faster for large files)
# Usage: remove_duplicate_lines_sorted file
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

# Remove multiple consecutive blank lines, leaving only one
# Usage: cat file | remove_multiple_blank_lines
remove_multiple_blank_lines() {
  sed '/^$/N;/^\n$/D'
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

# Extract lines matching a pattern (grep wrapper)
# Usage: extract_pattern "pattern" file
extract_pattern() {
  local pattern="$1"
  shift
  grep -E "$pattern" "$@"
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

# Count non-empty lines
# Usage: count_lines file
count_lines() {
  grep -c . "$@" 2>/dev/null || echo 0
}

# Normalize whitespace (convert tabs to spaces, collapse multiple spaces)
# Usage: cat file | normalize_whitespace
normalize_whitespace() {
  sed -e 's/\t/ /g' -e 's/  */ /g'
}

# Display colorized banner with gradient effect
# Usage: display_banner "banner_text" [colors...]
# Example: display_banner "$banner" "$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU"
display_banner() {
  local banner_text="$1"
  shift
  local -a flag_colors=("$@")
  
  # Default to trans flag colors if none provided
  if (( ${#flag_colors[@]} == 0 )); then
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
