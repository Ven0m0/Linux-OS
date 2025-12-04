#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Colors (trans palette)
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Core helpers
has(){ command -v "$1" &>/dev/null; }
xecho(){ printf '%b\n' "$*"; }
log(){ xecho "$*"; }
warn(){ xecho "${YLW}WARN:${DEF} $*"; }
err(){ xecho "${RED}ERROR:${DEF} $*" >&2; }
die(){ err "$*"; exit "${2:-1}"; }
dbg(){ [[ ${DEBUG:-0} -eq 1 ]] && xecho "[DBG] $*" || :; }

# Tool detection with fallbacks
FD=${FD:-$(command -v fd || command -v fdfind || echo '')}
RG=${RG:-$(command -v rg || command -v grep || echo '')}
SD=${SD:-$(command -v sd || command -v sed || echo '')}
PARALLEL=${PARALLEL:-$(command -v rust-parallel || command -v parallel || command -v xargs || echo '')}

# Safe workspace
WORKDIR=$(mktemp -d)
cleanup(){
  set +e
  [[ -d ${WORKDIR:-} ]] && rm -rf "${WORKDIR}" || :
}
on_err(){ err "failed at line ${1:-?}"; }
trap 'cleanup' EXIT
trap 'on_err $LINENO' ERR
trap ':' INT TERM

# Config
declare -A cfg=([dry_run]=0 [debug]=0 [quiet]=0 [fix]=1 [check_only]=0)
run(){ if (( cfg[dry_run] )); then log "[DRY] $*"; else "$@"; fi; }

# Global state
declare -A TOOL_MISSING=()
declare -a MODIFIED_FILES=()
declare -a ERROR_FILES=()
declare -a COMMANDS_RUN=()
declare -i TOTAL_ERRORS=0
declare -i TOTAL_MODIFIED=0

# File discovery
find_files(){
  local pattern=$1
  local -n result=$2
  local exclude_args=()

  # Common exclusions
  local exclude_dirs=(.git node_modules .cache .var .rustup .wine .zim .void-editor .vscode .claude Linux-Settings)

  if [[ -n $FD ]]; then
    for dir in "${exclude_dirs[@]}"; do
      exclude_args+=(--exclude "$dir")
    done
    # fd uses regex by default, use -e for extensions or -g for glob
    if [[ $pattern == *.* ]]; then
      # Extract extension(s)
      local ext_part="${pattern#*.}"
      if [[ $ext_part == *{*}* ]]; then
        # Multiple extensions like {yml,yaml}
        local exts="${ext_part#*\{}"
        exts="${exts%\}*}"
        IFS=',' read -ra ext_array <<< "$exts"
        local ext_args=()
        for ext in "${ext_array[@]}"; do
          ext_args+=(-e "$ext")
        done
        mapfile -t result < <("$FD" -tf "${exclude_args[@]}" "${ext_args[@]}")
      else
        # Single extension
        mapfile -t result < <("$FD" -tf "${exclude_args[@]}" -e "$ext_part")
      fi
    else
      mapfile -t result < <("$FD" -tf "${exclude_args[@]}" -g "$pattern")
    fi
  else
    local find_exclude=()
    for dir in "${exclude_dirs[@]}"; do
      find_exclude+=(-path "*/$dir" -prune -o)
    done
    # Handle glob patterns for find
    if [[ $pattern == *{*}* ]]; then
      # Multiple patterns - need to use -o for OR
      local patterns="${pattern#*\{}"
      patterns="${patterns%\}*}"
      local prefix="${pattern%%\{*}"
      IFS=',' read -ra pattern_array <<< "$patterns"
      local find_patterns=()
      for p in "${pattern_array[@]}"; do
        find_patterns+=(-name "${prefix}${p}" -o)
      done
      # Remove last -o
      unset 'find_patterns[-1]'
      mapfile -t result < <(find . "${find_exclude[@]}" -type f \( "${find_patterns[@]}" \) -print)
    else
      mapfile -t result < <(find . "${find_exclude[@]}" -type f -name "$pattern" -print)
    fi
  fi
}

# Check tool availability
check_tool(){
  local tool=$1
  local required=${2:-0}

  if ! has "$tool"; then
    TOOL_MISSING["$tool"]=1
    if (( required )); then
      warn "Required tool missing: $tool"
      return 1
    fi
    dbg "Optional tool missing: $tool"
    return 1
  fi
  return 0
}

# Format and lint YAML files
process_yaml(){
  log "${LBLU}→${DEF} Processing YAML files..."
  local -a files=()
  find_files "*.{yml,yaml}" files

  (( ${#files[@]} == 0 )) && { log "  No YAML files found"; return 0; }
  log "  Found ${#files[@]} YAML files"

  # Format with yamlfmt
  if check_tool yamlfmt; then
    log "  ${PNK}Formatting${DEF} with yamlfmt..."
    local cmd="yamlfmt"
    (( cfg[fix] )) && cmd+=" -formatter retain_line_breaks=true"

    local -i errors=0
    for file in "${files[@]}"; do
      if (( cfg[fix] )); then
        if $cmd "$file" 2>/dev/null; then
          MODIFIED_FILES+=("$file")
          ((TOTAL_MODIFIED++))
        else
          ((errors++))
          ERROR_FILES+=("$file")
        fi
      fi
    done
    COMMANDS_RUN+=("yamlfmt <file>")
    ((TOTAL_ERRORS += errors))
  else
    warn "  yamlfmt not found, skipping format"
  fi

  # Lint with yamllint
  if check_tool yamllint; then
    log "  ${BWHT}Linting${DEF} with yamllint..."
    local -i errors=0
    for file in "${files[@]}"; do
      if ! yamllint -f parsable "$file" &>/dev/null; then
        ((errors++))
        ERROR_FILES+=("$file")
      fi
    done
    COMMANDS_RUN+=("yamllint -f parsable <file>")
    ((TOTAL_ERRORS += errors))
    (( errors > 0 )) && warn "  Found $errors files with yamllint errors"
  else
    warn "  yamllint not found, skipping lint"
  fi

  # Lint GitHub Actions with actionlint
  local -a action_files=()
  mapfile -t action_files < <(printf '%s\n' "${files[@]}" | grep -E '\.github/workflows/')

  if (( ${#action_files[@]} > 0 )) && check_tool actionlint; then
    log "  ${BWHT}Linting${DEF} GitHub Actions with actionlint..."
    local -i errors=0
    for file in "${action_files[@]}"; do
      if ! actionlint "$file" &>/dev/null; then
        ((errors++))
        ERROR_FILES+=("$file")
      fi
    done
    COMMANDS_RUN+=("actionlint <file>")
    ((TOTAL_ERRORS += errors))
    (( errors > 0 )) && warn "  Found $errors files with actionlint errors"
  fi
}

# Format and lint JSON files
process_json(){
  log "${LBLU}→${DEF} Processing JSON files..."
  local -a files=()
  find_files "*.{json,json5,jsonc}" files

  (( ${#files[@]} == 0 )) && { log "  No JSON files found"; return 0; }
  log "  Found ${#files[@]} JSON files"

  # Try biome first, fallback to prettier
  if check_tool biome; then
    log "  ${PNK}Formatting${DEF} with biome..."
    if (( cfg[fix] )); then
      if biome format --write "${files[@]}" 2>/dev/null; then
        MODIFIED_FILES+=("${files[@]}")
        ((TOTAL_MODIFIED += ${#files[@]}))
      fi
      biome check --apply "${files[@]}" 2>/dev/null || :
    else
      if ! biome check "${files[@]}" 2>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("biome format --write <file>" "biome check --apply <file>")
  elif check_tool prettier; then
    log "  ${PNK}Formatting${DEF} with prettier..."
    if (( cfg[fix] )); then
      for file in "${files[@]}"; do
        if prettier --write "$file" &>/dev/null; then
          MODIFIED_FILES+=("$file")
          ((TOTAL_MODIFIED++))
        fi
      done
    else
      if ! prettier --check "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("prettier --write <file>")
  else
    warn "  No JSON formatter found (biome/prettier)"
  fi
}

# Format and lint shell scripts
process_shell(){
  log "${LBLU}→${DEF} Processing shell scripts..."
  local -a files=()
  find_files "*.{sh,bash}" files

  (( ${#files[@]} == 0 )) && { log "  No shell scripts found"; return 0; }
  log "  Found ${#files[@]} shell scripts"

  # Format with shfmt
  if check_tool shfmt; then
    log "  ${PNK}Formatting${DEF} with shfmt..."
    if (( cfg[fix] )); then
      if shfmt -w -i 2 -ci -sr "${files[@]}" 2>/dev/null; then
        MODIFIED_FILES+=("${files[@]}")
        ((TOTAL_MODIFIED += ${#files[@]}))
      fi
    else
      if ! shfmt -d -i 2 -ci -sr "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("shfmt -w -i 2 -ci -sr <file>")
  else
    warn "  shfmt not found, skipping format"
  fi

  # Lint with shellcheck
  if check_tool shellcheck; then
    log "  ${BWHT}Linting${DEF} with shellcheck..."
    local -i errors=0
    for file in "${files[@]}"; do
      if ! shellcheck --format=gcc "$file" &>/dev/null; then
        ((errors++))
        ERROR_FILES+=("$file")
      fi
    done
    COMMANDS_RUN+=("shellcheck --format=gcc <file>")
    ((TOTAL_ERRORS += errors))
    (( errors > 0 )) && warn "  Found $errors files with shellcheck errors"
  else
    warn "  shellcheck not found, skipping lint"
  fi

  # Audit with shellharden (optional)
  if check_tool shellharden; then
    log "  ${BWHT}Auditing${DEF} with shellharden..."
    for file in "${files[@]}"; do
      if (( cfg[fix] )); then
        shellharden --replace "$file" &>/dev/null || :
      else
        shellharden --check "$file" &>/dev/null || :
      fi
    done
    COMMANDS_RUN+=("shellharden --check <file>")
  fi
}

# Format fish scripts
process_fish(){
  log "${LBLU}→${DEF} Processing fish scripts..."
  local -a files=()
  find_files "*.fish" files

  (( ${#files[@]} == 0 )) && { log "  No fish scripts found"; return 0; }
  log "  Found ${#files[@]} fish scripts"

  if check_tool fish_indent; then
    log "  ${PNK}Formatting${DEF} with fish_indent..."
    if (( cfg[fix] )); then
      for file in "${files[@]}"; do
        if fish_indent -w "$file" 2>/dev/null; then
          MODIFIED_FILES+=("$file")
          ((TOTAL_MODIFIED++))
        fi
      done
    fi
    COMMANDS_RUN+=("fish_indent -w <file>")
  else
    warn "  fish_indent not found, skipping"
  fi
}

# Format and lint TOML files
process_toml(){
  log "${LBLU}→${DEF} Processing TOML files..."
  local -a files=()
  find_files "*.toml" files

  (( ${#files[@]} == 0 )) && { log "  No TOML files found"; return 0; }
  log "  Found ${#files[@]} TOML files"

  # Format with taplo
  if check_tool taplo; then
    log "  ${PNK}Formatting${DEF} with taplo..."
    if (( cfg[fix] )); then
      if taplo format "${files[@]}" 2>/dev/null; then
        MODIFIED_FILES+=("${files[@]}")
        ((TOTAL_MODIFIED += ${#files[@]}))
      fi
    else
      if ! taplo format --check "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("taplo format <file>")
  else
    warn "  taplo not found, skipping format"
  fi

  # Lint with tombi (if available)
  if check_tool tombi; then
    log "  ${BWHT}Linting${DEF} with tombi..."
    local -i errors=0
    for file in "${files[@]}"; do
      if ! tombi lint "$file" &>/dev/null; then
        ((errors++))
        ERROR_FILES+=("$file")
      fi
    done
    COMMANDS_RUN+=("tombi lint <file>")
    ((TOTAL_ERRORS += errors))
  fi
}

# Format and lint Markdown files
process_markdown(){
  log "${LBLU}→${DEF} Processing Markdown files..."
  local -a files=()
  find_files "*.{md,markdown}" files

  (( ${#files[@]} == 0 )) && { log "  No Markdown files found"; return 0; }
  log "  Found ${#files[@]} Markdown files"

  # Format with mdformat
  if check_tool mdformat; then
    log "  ${PNK}Formatting${DEF} with mdformat..."
    if (( cfg[fix] )); then
      for file in "${files[@]}"; do
        if mdformat "$file" 2>/dev/null; then
          MODIFIED_FILES+=("$file")
          ((TOTAL_MODIFIED++))
        fi
      done
    else
      if ! mdformat --check "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("mdformat <file>")
  else
    warn "  mdformat not found, skipping format"
  fi

  # Lint with markdownlint
  if check_tool markdownlint; then
    log "  ${BWHT}Linting${DEF} with markdownlint..."
    if (( cfg[fix] )); then
      markdownlint --fix "${files[@]}" 2>/dev/null || :
    fi

    local -i errors=0
    for file in "${files[@]}"; do
      if ! markdownlint "$file" &>/dev/null; then
        ((errors++))
        ERROR_FILES+=("$file")
      fi
    done
    COMMANDS_RUN+=("markdownlint --fix <file>")
    ((TOTAL_ERRORS += errors))
    (( errors > 0 )) && warn "  Found $errors files with markdownlint errors"
  else
    warn "  markdownlint not found, skipping lint"
  fi
}

# Format and lint Python files
process_python(){
  log "${LBLU}→${DEF} Processing Python files..."
  local -a files=()
  find_files "*.{py,pyw,pyi}" files

  (( ${#files[@]} == 0 )) && { log "  No Python files found"; return 0; }
  log "  Found ${#files[@]} Python files"

  # Fix with ruff
  if check_tool ruff; then
    log "  ${PNK}Fixing${DEF} with ruff..."
    if (( cfg[fix] )); then
      ruff check --fix "${files[@]}" 2>/dev/null || :
      MODIFIED_FILES+=("${files[@]}")
    else
      if ! ruff check "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("ruff check --fix <file>")
  else
    warn "  ruff not found, skipping"
  fi

  # Format with black
  if check_tool black; then
    log "  ${PNK}Formatting${DEF} with black..."
    if (( cfg[fix] )); then
      if black --fast "${files[@]}" 2>/dev/null; then
        MODIFIED_FILES+=("${files[@]}")
        ((TOTAL_MODIFIED += ${#files[@]}))
      fi
    else
      if ! black --check "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("black --fast <file>")
  else
    warn "  black not found, skipping format"
  fi
}

# Format and lint Lua files
process_lua(){
  log "${LBLU}→${DEF} Processing Lua files..."
  local -a files=()
  find_files "*.lua" files

  (( ${#files[@]} == 0 )) && { log "  No Lua files found"; return 0; }
  log "  Found ${#files[@]} Lua files"

  # Format with stylua
  if check_tool stylua; then
    log "  ${PNK}Formatting${DEF} with stylua..."
    if (( cfg[fix] )); then
      if stylua "${files[@]}" 2>/dev/null; then
        MODIFIED_FILES+=("${files[@]}")
        ((TOTAL_MODIFIED += ${#files[@]}))
      fi
    else
      if ! stylua --check "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("stylua <file>")
  else
    warn "  stylua not found, skipping format"
  fi

  # Lint with selene
  if check_tool selene; then
    log "  ${BWHT}Linting${DEF} with selene..."
    local -i errors=0
    for file in "${files[@]}"; do
      if ! selene "$file" &>/dev/null; then
        ((errors++))
        ERROR_FILES+=("$file")
      fi
    done
    COMMANDS_RUN+=("selene <file>")
    ((TOTAL_ERRORS += errors))
    (( errors > 0 )) && warn "  Found $errors files with selene errors"
  else
    warn "  selene not found, skipping lint"
  fi
}

# Format CSS/HTML/JS files
process_web(){
  log "${LBLU}→${DEF} Processing web files (CSS/HTML/JS)..."
  local -a files=()
  find_files "*.{css,scss,sass,less,html,htm,js,mjs,cjs,jsx,ts,tsx}" files

  (( ${#files[@]} == 0 )) && { log "  No web files found"; return 0; }
  log "  Found ${#files[@]} web files"

  # Try biome first, fallback to prettier
  if check_tool biome; then
    log "  ${PNK}Formatting${DEF} with biome..."
    if (( cfg[fix] )); then
      biome format --write "${files[@]}" 2>/dev/null || :
      biome check --apply "${files[@]}" 2>/dev/null || :
      MODIFIED_FILES+=("${files[@]}")
      ((TOTAL_MODIFIED += ${#files[@]}))
    else
      if ! biome check "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("biome format --write <file>" "biome check --apply <file>")
  elif check_tool prettier; then
    log "  ${PNK}Formatting${DEF} with prettier..."
    if (( cfg[fix] )); then
      prettier --write "${files[@]}" 2>/dev/null || :
      MODIFIED_FILES+=("${files[@]}")
      ((TOTAL_MODIFIED += ${#files[@]}))
    else
      if ! prettier --check "${files[@]}" &>/dev/null; then
        ((TOTAL_ERRORS++)) || :
      fi
    fi
    COMMANDS_RUN+=("prettier --write <file>")
  else
    warn "  No web formatter found (biome/prettier)"
  fi

  # Lint JS/TS with eslint
  local -a js_files=()
  mapfile -t js_files < <(printf '%s\n' "${files[@]}" | grep -E '\.(js|mjs|cjs|jsx|ts|tsx)$')

  if (( ${#js_files[@]} > 0 )) && check_tool eslint; then
    log "  ${BWHT}Linting${DEF} with eslint..."
    if (( cfg[fix] )); then
      eslint --fix "${js_files[@]}" 2>/dev/null || :
    fi

    local -i errors=0
    for file in "${js_files[@]}"; do
      if ! eslint "$file" &>/dev/null; then
        ((errors++))
        ERROR_FILES+=("$file")
      fi
    done
    COMMANDS_RUN+=("eslint --fix <file>")
    ((TOTAL_ERRORS += errors))
  fi
}

# Format XML files
process_xml(){
  log "${LBLU}→${DEF} Processing XML files..."
  local -a files=()
  find_files "*.{xml,svg}" files

  (( ${#files[@]} == 0 )) && { log "  No XML files found"; return 0; }
  log "  Found ${#files[@]} XML files"

  if check_tool xmllint; then
    log "  ${PNK}Formatting${DEF} with xmllint..."
    if (( cfg[fix] )); then
      for file in "${files[@]}"; do
        if xmllint --format "$file" -o "$file" 2>/dev/null; then
          MODIFIED_FILES+=("$file")
          ((TOTAL_MODIFIED++))
        fi
      done
    fi
    COMMANDS_RUN+=("xmllint --format <file> -o <file>")
  else
    warn "  xmllint not found, skipping"
  fi
}

# Print summary
print_summary(){
  log ""
  log "${BLD}${LBLU}═══════════════════════════════════════════════════════════════${DEF}"
  log "${BLD}${PNK}                    LINT & FORMAT SUMMARY${DEF}"
  log "${BLD}${LBLU}═══════════════════════════════════════════════════════════════${DEF}"
  log ""

  # Unique counts
  local -i unique_modified=0
  local -i unique_errors=0

  if (( ${#MODIFIED_FILES[@]} > 0 )); then
    unique_modified=$(printf '%s\n' "${MODIFIED_FILES[@]}" | sort -u | wc -l)
  fi

  if (( ${#ERROR_FILES[@]} > 0 )); then
    unique_errors=$(printf '%s\n' "${ERROR_FILES[@]}" | sort -u | wc -l)
  fi

  log "${GRN}✓${DEF} Modified files: ${BLD}${unique_modified}${DEF}"
  log "${RED}✗${DEF} Files with errors: ${BLD}${unique_errors}${DEF}"
  log "${YLW}⚠${DEF} Total error count: ${BLD}${TOTAL_ERRORS}${DEF}"
  log ""

  # Missing tools
  if (( ${#TOOL_MISSING[@]} > 0 )); then
    log "${YLW}Missing tools:${DEF}"
    for tool in "${!TOOL_MISSING[@]}"; do
      log "  - $tool"
    done
    log ""
  fi

  # Commands to reproduce
  if (( ${#COMMANDS_RUN[@]} > 0 )); then
    log "${BWHT}Commands to reproduce:${DEF}"
    printf '%s\n' "${COMMANDS_RUN[@]}" | sort -u | while IFS= read -r cmd; do
      log "  ${CYN}$cmd${DEF}"
    done
    log ""
  fi

  # Exit with error if issues found
  if (( unique_errors > 0 || TOTAL_ERRORS > 0 )); then
    log "${RED}${BLD}FAIL:${DEF} Linting/formatting found ${TOTAL_ERRORS} errors in ${unique_errors} files"
    return 1
  else
    log "${GRN}${BLD}PASS:${DEF} All checks passed!"
    return 0
  fi
}

# Parse args
parse_args(){
  while (($#)); do
    case "$1" in
      -q|--quiet) cfg[quiet]=1;;
      -v|--verbose) cfg[debug]=1; DEBUG=1;;
      -n|--dry-run) cfg[dry_run]=1;;
      -c|--check) cfg[fix]=0; cfg[check_only]=1;;
      --help|-h)
        cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Comprehensive lint and format enforcement for all file types.

OPTIONS:
  -q, --quiet       Suppress output
  -v, --verbose     Verbose/debug output
  -n, --dry-run     Show what would be done
  -c, --check       Check only, don't fix
  -h, --help        Show this help

File groups processed:
  - YAML (yamlfmt, yamllint, actionlint)
  - JSON (biome/prettier)
  - Shell (shfmt, shellcheck, shellharden)
  - Fish (fish_indent)
  - TOML (taplo, tombi)
  - Markdown (mdformat, markdownlint)
  - Python (ruff, black)
  - Lua (stylua, selene)
  - Web (biome/prettier, eslint)
  - XML (xmllint)

Exit codes:
  0 - All checks passed
  1 - Errors found

EOF
        exit 0
        ;;
      --version) printf '%s\n' "1.0.0"; exit 0;;
      --) shift; break;;
      -*) die "invalid option: $1";;
      *) break;;
    esac
    shift
  done
}

main(){
  parse_args "$@"
  (( cfg[quiet] )) && exec >/dev/null
  (( cfg[debug] )) && dbg "verbose on"

  log "${BLD}${PNK}Starting comprehensive lint & format...${DEF}"
  log ""

  # Process all file types
  process_yaml
  process_json
  process_shell
  process_fish
  process_toml
  process_markdown
  process_python
  process_lua
  process_web
  process_xml

  # Print summary and exit with proper code
  trap - ERR
  set +e
  print_summary
  exit $?
}

main "$@"
