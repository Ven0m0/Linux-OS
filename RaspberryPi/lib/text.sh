#!/usr/bin/env bash
# Text processing utilities library
# Contains shared functions for text manipulation and file processing

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
