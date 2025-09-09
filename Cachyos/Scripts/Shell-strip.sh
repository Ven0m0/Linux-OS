#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8

usage() {
  cat <<EOF >&2
Usage: $0 [options] <script.sh>

Options:
  --fmt           Run shfmt (format code, no minify)
  --minify        Run shfmt (format + minify)
  --strip-sep     Strip comment separators (-----)
  --strip-copyright Strip leading copyright/license header
  --strip-comments Remove all comment lines
  --no-fmt        Skip shfmt entirely
  --no-harden     Skip shellharden
  --no-lint       Skip ShellCheck patching
  -h, --help      Show this help
EOF
  exit "${1:-1}"
}

# Defaults
DO_FMT=true
MINIFY=false
DO_HARDEN=true
DO_LINT=true
STRIP_SEP=false
STRIP_COPY=false
STRIP_COMMENTS=false

# Parse flags (all before the file argument)
while [[ $# -gt 1 ]]; do
  case $1 in
    --fmt)             MINIFY=false; DO_FMT=true; shift ;;
    --minify)          MINIFY=true;  DO_FMT=true; shift ;;
    --no-fmt)          DO_FMT=false; shift ;;
    --no-harden)       DO_HARDEN=false; shift ;;
    --no-lint)         DO_LINT=false; shift ;;
    --strip-sep)       STRIP_SEP=true; shift ;;
    --strip-copyright) STRIP_COPY=true; shift ;;
    --strip-comments)  STRIP_COMMENTS=true; shift ;;
    -h|--help)         usage 0 ;;
    *)                 break ;;
  esac
done

FILE="${1:?Usage: $0 [options] <script.sh>}"
cp "$FILE" "$FILE.bak"
TARGET_FILE="$FILE"

# Define strip functions
pp_strip_separators()   { awk '/^#\s*-{5,}/ { next } { print }'; }
pp_strip_copyright()    { awk '/^#/ { if(!p){ next } } { p=1; print }'; }
pp_strip_comments()     { sed '/^[[:space:]]*#.*$/d'; }

if $STRIP_SEP || $STRIP_COPY || $STRIP_COMMENTS; then
  TMPFILE="$(mktemp)"
  cp "$FILE" "$TMPFILE"
  CONTENT="$(cat "$TMPFILE")"
  $STRIP_SEP       && CONTENT="$(printf '%s' "$CONTENT" | pp_strip_separators)"
  $STRIP_COPY      && CONTENT="$(printf '%s' "$CONTENT" | pp_strip_copyright)"
  $STRIP_COMMENTS  && CONTENT="$(printf '%s' "$CONTENT" | pp_strip_comments)"
  printf '%s\n' "$CONTENT" > "$TMPFILE"
  TARGET_FILE="$TMPFILE"
fi

if $DO_FMT; then
  if $MINIFY; then
    shfmt -ln=bash -i 2 -mn -ci -bn -mn -w "$TARGET_FILE"
  else
    shfmt -ln=bash -i 2 -s -ci -bn -w "$TARGET_FILE"
  fi
fi

if $DO_HARDEN; then
  shellharden --transform --replace "$TARGET_FILE"
fi

# 4) Optional ShellCheck auto-fix
if $DO_LINT; then
  shellcheck -s bash --exclude=SC2054 --format=diff "$TARGET_FILE" | patch "$TARGET_FILE" || true
fi

# If a temp file was created, move it back to the original path
if [[ "$TARGET_FILE" != "$FILE" ]]; then
  mv "$TARGET_FILE" "$FILE"
fi

echo "Auto-fix complete for: $FILE"
echo "Backup saved as: $FILE.bak"
