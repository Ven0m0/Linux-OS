#!/usr/bin/env bash
# Comprehensive bash script auditor
# Checks for performance issues, inefficient patterns, and code quality
set -eu # No pipefail - we need partial grep matches
shopt -s nullglob globstar
IFS=$'\n\t'

RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' DEF=$'\e[0m' BLD=$'\e[1m'

has() { command -v "$1" &> /dev/null; }

# Tool detection with fallbacks
FD=$(command -v fd || command -v fdfind || echo "")

declare -i total_issues=0
declare -A issues_by_type=(
  [nested_subshells]=0
  [eval_usage]=0
  [uuoc]=0
  [ls_parsing]=0
  [pipe_to_while]=0
  [cat_proc]=0
  [backticks]=0
  [missing_safety]=0
  [unquoted_array]=0
)

check_script() {
  local script=$1
  local -i script_issues=0
  local result line1

  # Skip non-bash scripts
  line1=$(head -n1 "$script" 2> /dev/null) || return 0
  [[ $line1 =~ ^'#!'.*'bash' || $line1 =~ ^'#!'.*'/sh' ]] || return 0

  printf '%s\n' "${BLU}Checking:${DEF} $script"

  # 1. Nested subshells: $(outer $(inner))
  result=$(grep -nE '\$\([^)]*\$\(' "$script" 2> /dev/null | head -3 || true)
  if [[ -n $result ]]; then
    printf '  %s\n' "${YLW}⚠ Nested subshells${DEF}"
    ((issues_by_type[nested_subshells]++)) || :
    ((script_issues++)) || :
  fi

  # 2. Eval usage (exclude necessary dbus-launch/apt-config patterns)
  result=$(grep -nE '\beval\b' "$script" 2> /dev/null | grep -vE 'dbus-launch|apt-config|ssh-agent' | head -3 || true)
  if [[ -n $result ]]; then
    printf '  %s\n' "${YLW}⚠ Potentially unsafe eval${DEF}"
    ((issues_by_type[eval_usage]++)) || :
    ((script_issues++)) || :
  fi

  # 3. UUOC (Useless Use of Cat)
  result=$(grep -nE '\bcat\s+[^|]*\|\s*(grep|awk|sed|head|tail)' "$script" 2> /dev/null | head -3 || true)
  if [[ -n $result ]]; then
    printf '  %s\n' "${YLW}⚠ Useless use of cat (UUOC)${DEF}"
    ((issues_by_type[uuoc]++)) || :
    ((script_issues++)) || :
  fi

  # 4. ls parsing
  result=$(grep -nE 'for\s+\w+\s+in\s+\$\(ls' "$script" 2> /dev/null | head -3 || true)
  if [[ -n $result ]]; then
    printf '  %s\n' "${RED}✗ Parsing ls output (DANGEROUS)${DEF}"
    ((issues_by_type[ls_parsing]++)) || :
    ((script_issues++)) || :
  fi

  # 5. Pipe to while (variables lost in subshell)
  result=$(grep -nE '^\s*[^#]*\|\s*while\s+(IFS=)?\s*read' "$script" 2> /dev/null | head -3 || true)
  if [[ -n $result ]]; then
    printf '  %s\n' "${YLW}⚠ Pipe to while (use process substitution)${DEF}"
    ((issues_by_type[pipe_to_while]++)) || :
    ((script_issues++)) || :
  fi

  # 6. cat /proc files (should use redirection)
  result=$(grep -nE '\bcat\s+/proc/' "$script" 2> /dev/null | head -3 || true)
  if [[ -n $result ]]; then
    printf '  %s\n' "${YLW}⚠ Using cat on /proc (use redirection)${DEF}"
    ((issues_by_type[cat_proc]++)) || :
    ((script_issues++)) || :
  fi

  # 7. Backtick command substitution
  result=$(grep -nE '`[^`]+`' "$script" 2> /dev/null | grep -v '^[[:space:]]*#' | head -3 || true)
  if [[ -n $result ]]; then
    printf '  %s\n' "${YLW}⚠ Backticks (use \$(...) instead)${DEF}"
    ((issues_by_type[backticks]++)) || :
    ((script_issues++)) || :
  fi

  # 8. Missing set -e/-u/pipefail
  if ! grep -qE '^set\s+.*-[euo]' "$script" 2> /dev/null; then
    printf '  %s\n' "${YLW}⚠ Missing set -euo pipefail${DEF}"
    ((issues_by_type[missing_safety]++)) || :
    ((script_issues++)) || :
  fi

  # 9. Unquoted array expansion
  result=$(grep -nE '\$\{[a-zA-Z_][a-zA-Z0-9_]*\[@\]\}' "$script" 2> /dev/null | grep -v '"' | head -3 || true)
  if [[ -n $result ]]; then
    printf '  %s\n' "${YLW}⚠ Unquoted array expansion${DEF}"
    ((issues_by_type[unquoted_array]++)) || :
    ((script_issues++)) || :
  fi

  if ((script_issues == 0)); then
    printf '  %s\n' "${GRN}✓ No issues${DEF}"
  fi

  ((total_issues += script_issues)) || :
  printf '\n'
}

main() {
  local -a scripts=()

  printf '%s\n\n' "${BLD}${BLU}=== Bash Script Audit ===${DEF}"

  # Find scripts using fd or find
  if [[ -n $FD ]]; then
    mapfile -t scripts < <("$FD" -H -t f -e sh . --exclude .git 2> /dev/null | sort)
  else
    mapfile -t scripts < <(find . -type f -name '*.sh' ! -path './.git/*' 2> /dev/null | sort)
  fi

  printf 'Found %s%d%s bash scripts to audit\n\n' "$BLD" "${#scripts[@]}" "$DEF"

  for script in "${scripts[@]}"; do
    check_script "$script"
  done

  printf '%s\n' "${BLD}${BLU}=== Summary ===${DEF}"
  printf 'Total issues: %s%d%s\n\n' "$BLD" "$total_issues" "$DEF"

  printf 'Issues by type:\n'
  local type
  for type in "${!issues_by_type[@]}"; do
    if ((issues_by_type[$type] > 0)); then
      printf '  %-20s %d\n' "$type:" "${issues_by_type[$type]}"
    fi
  done

  # Exit with error if issues found
  ((total_issues == 0))
}

main "$@"
