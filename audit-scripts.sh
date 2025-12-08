#!/usr/bin/env bash
#  Comprehensive bash script auditor
# Checks for performance issues, inefficient patterns, and code quality

set -eu # No pipefail for this audit script
shopt -s nullglob globstar
IFS=$'\n\t'

RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MGN=$'\e[35m' DEF=$'\e[0m' BLD=$'\e[1m'

declare -i total_issues=0
declare -A issues_by_type=(
  [nested_subshells]=0
  [eval_usage]=0
  [uuoc]=0
  [ls_parsing]=0
  [unquoted_vars]=0
  [pipe_to_while]=0
  [cat_proc]=0
)

check_script() {
  local script=$1
  local -i script_issues=0
  local result

  # Skip non-bash scripts
  head -n1 "$script" | grep -qE '^#!/.*(ba)?sh' || return 0

  printf "${BLU}Checking: %s${DEF}\n" "$script"

  # 1. Nested subshells: $(outer $(inner))
  result=$(grep -nE '\$\([^)]*\$\(' "$script" 2> /dev/null | head -5 || true)
  if [[ -n $result ]]; then
    printf "  ${YLW}⚠ Nested subshells found${DEF}\n"
    issues_by_type[nested_subshells]=$((issues_by_type[nested_subshells] + 1))
    script_issues=$((script_issues + 1))
  fi

  # 2. Eval usage (exclude necessary dbus-launch pattern)
  result=$(grep -nE '\beval\b' "$script" 2> /dev/null | grep -vE 'dbus-launch|apt-config' | head -5 || true)
  if [[ -n $result ]]; then
    printf "  ${YLW}⚠ Potentially unsafe eval usage${DEF}\n"
    issues_by_type[eval_usage]=$((issues_by_type[eval_usage] + 1))
    script_issues=$((script_issues + 1))
  fi

  # 3. UUOC (Useless Use of Cat)
  result=$(grep -nE '\bcat\s+[^|]*\s*\|\s*(grep|awk|sed)' "$script" 2> /dev/null | head -5 || true)
  if [[ -n $result ]]; then
    printf "  ${YLW}⚠ Useless use of cat (UUOC)${DEF}\n"
    issues_by_type[uuoc]=$((issues_by_type[uuoc] + 1))
    script_issues=$((script_issues + 1))
  fi

  # 4. ls parsing
  result=$(grep -nE 'for\s+\w+\s+in\s+\$\(ls\s' "$script" 2> /dev/null | head -5 || true)
  if [[ -n $result ]]; then
    printf "  ${RED}✗ Parsing ls output (DANGEROUS)${DEF}\n"
    issues_by_type[ls_parsing]=$((issues_by_type[ls_parsing] + 1))
    script_issues=$((script_issues + 1))
  fi

  # 5. Pipe to while (variables lost in subshell)
  result=$(grep -nE '^\s*[^#]*\|\s*while\s+(IFS=)?\s*read' "$script" 2> /dev/null | head -5 || true)
  if [[ -n $result ]]; then
    printf "  ${YLW}⚠ Pipe to while (variables may be lost)${DEF}\n"
    issues_by_type[pipe_to_while]=$((issues_by_type[pipe_to_while] + 1))
    script_issues=$((script_issues + 1))
  fi

  # 6. cat /proc files (should use redirection)
  result=$(grep -nE '\bcat\s+/proc/' "$script" 2> /dev/null | head -5 || true)
  if [[ -n $result ]]; then
    printf "  ${YLW}⚠ Using cat on /proc files (use redirection)${DEF}\n"
    issues_by_type[cat_proc]=$((issues_by_type[cat_proc] + 1))
    script_issues=$((script_issues + 1))
  fi

  if ((script_issues == 0)); then
    printf "  ${GRN}✓ No issues found${DEF}\n"
  fi

  total_issues=$((total_issues + script_issues))
  printf "\n"
}

main() {
  printf "${BLD}${BLU}=== Bash Script Audit ===${DEF}\n\n"

  mapfile -t scripts < <(find . -type f -name '*.sh' ! -path './.git/*' | sort)

  printf "Found ${BLD}%d${DEF} bash scripts to audit\n\n" "${#scripts[@]}"

  for script in "${scripts[@]}"; do
    check_script "$script"
  done

  printf "${BLD}${BLU}=== Summary ===${DEF}\n"
  printf "Total issues found: ${BLD}%d${DEF}\n\n" "$total_issues"
  printf "Issues by type:\n"
  for type in "${!issues_by_type[@]}"; do
    if ((issues_by_type[$type] > 0)); then
      printf "  %s: %d\n" "$type" "${issues_by_type[$type]}"
    fi
  done
}

main "$@"
