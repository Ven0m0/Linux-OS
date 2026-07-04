#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Colors
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' DEF=$'\e[0m'
has() { command -v "$1" &>/dev/null; }
log() { printf '%b%s%b\n' "${LBLU}" "$*" "${DEF}"; }

CHECK=0
[[ "${1:-}" == "-c" || "${1:-}" == "--check" ]] && CHECK=1

FD=${FD:-""}
if [[ -z "$FD" ]]; then
  if has fdfind; then FD="fdfind"; elif has fd; then FD="fd"; fi
fi

# Shell scripts
if has shellcheck || has shfmt; then
  log "🐚 Linting and formatting Shell scripts..."
  # Use shfmt -i 2 -bn -ci -s -ln bash as per AGENTS.md
  # Use shellcheck --severity=style for zero warnings as per AGENTS.md
  if [[ -n "$FD" ]]; then
    if has shfmt; then
      OPTS=(-i 2 -bn -ci -s -ln bash)
      (( CHECK )) && OPTS+=(-d) || OPTS+=(-w)
      "$FD" -t f -e sh --exclude "WIP" --exclude ".github/agents" -X shfmt "${OPTS[@]}"
    fi
    has shellcheck && "$FD" -t f -e sh --exclude "WIP" --exclude ".github/agents" -X shellcheck --severity=style
  else
    local -a files=()
    while IFS= read -r f; do
      [[ $f == *"WIP"* || $f == *".github/agents"* ]] && continue
      files+=("$f")
    done < <(find . -type f -name "*.sh")
    if (( ${#files[@]} > 0 )); then
      if has shfmt; then
        if [[ $CHECK -eq 0 ]]; then
          shfmt -i 2 -bn -ci -s -ln bash -w "${files[@]}"
        else
          shfmt -i 2 -bn -ci -s -ln bash -d "${files[@]}"
        fi
      fi
      has shellcheck && shellcheck --severity=style "${files[@]}"
    fi
  fi
fi

# Python
if has ruff; then
  log "🐍 Linting and formatting Python..."
  R_EXCLUDE="Cachyos/Scripts/WIP,.github/agents"
  if [[ $CHECK -eq 1 ]]; then
    ruff check . --exclude "$R_EXCLUDE"
    ruff format --check . --exclude "$R_EXCLUDE"
  else
    ruff check --fix . --exclude "$R_EXCLUDE"
    ruff format . --exclude "$R_EXCLUDE"
  fi
fi

# Prettier (General)
if has prettier; then
  log "🎨 Formatting with Prettier..."
  P_OPTS=$([[ $CHECK -eq 1 ]] && echo "--check" || echo "--write")
  if [[ -n "$FD" ]]; then
    "$FD" -t f -e md -e json -e yml -e yaml --exclude "WIP" --exclude ".github/agents" -X prettier "$P_OPTS"
  else
    prettier "$P_OPTS" --ignore-path .gitignore .
  fi
fi

# YAML
if has yamllint; then
  log "🔍 Linting YAML..."
  yamllint .
fi

# Actionlint
if has actionlint; then
  log "🤖 Linting GitHub Actions..."
  actionlint
fi

log "✅ Done!"
