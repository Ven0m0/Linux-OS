#!/usr/bin/env bash
# Validation script for all Bash scripts in the repository
# Checks syntax and runs linters if available

set -euo pipefail

# Colors
RED=$'\e[31m'
GRN=$'\e[32m'
YLW=$'\e[33m'
DEF=$'\e[0m'

# Counters
total=0
passed=0
failed=0
warnings=0

# Check if command exists
has() {
  command -v "$1" &>/dev/null
}

# Print with color
print_status() {
  local status=$1 file=$2 message=${3:-}
  case "$status" in
    pass)
      printf '%s✓%s %s\n' "$GRN" "$DEF" "$file"
      ;;
    fail)
      printf '%s✗%s %s: %s\n' "$RED" "$DEF" "$file" "$message"
      ;;
    warn)
      printf '%s⚠%s %s: %s\n' "$YLW" "$DEF" "$file" "$message"
      ;;
  esac
}

# Validate bash syntax
validate_syntax() {
  local file=$1
  local output

  if output=$(bash -n "$file" 2>&1); then
    return 0
  else
    echo "$output"
    return 1
  fi
}

# Run shellcheck if available
run_shellcheck() {
  local file=$1

  if ! has shellcheck; then
    return 0
  fi

  if shellcheck "$file" 2>/dev/null; then
    return 0
  else
    return 2  # Warning, not fatal
  fi
}

# Run shfmt if available
run_shfmt() {
  local file=$1

  if ! has shfmt; then
    return 0
  fi

  if shfmt -d "$file" >/dev/null 2>&1; then
    return 0
  else
    return 2  # Warning, not fatal
  fi
}

# Main validation
echo "🔍 Validating all Bash scripts..."
echo

# Find all .sh files
while IFS= read -r -d '' file; do
  ((total++))

  # Check syntax (required)
  if ! error_msg=$(validate_syntax "$file" 2>&1); then
    print_status fail "$file" "Syntax error: $error_msg"
    ((failed++))
    continue
  fi

  # Run shellcheck (optional)
  shellcheck_result=0
  run_shellcheck "$file" || shellcheck_result=$?

  # Run shfmt (optional)
  shfmt_result=0
  run_shfmt "$file" || shfmt_result=$?

  # Determine overall status
  if [[ $shellcheck_result -eq 0 && $shfmt_result -eq 0 ]]; then
    print_status pass "$file"
    ((passed++))
  elif [[ $shellcheck_result -eq 2 || $shfmt_result -eq 2 ]]; then
    print_status warn "$file" "Linter warnings"
    ((warnings++))
    ((passed++))  # Still passes syntax check
  fi

done < <(find . -name '*.sh' -type f -print0)

# Print summary
echo
echo "======================================"
echo "Validation Summary"
echo "======================================"
echo "Total scripts:    $total"
echo "Passed:           ${GRN}${passed}${DEF}"
echo "Failed:           ${RED}${failed}${DEF}"
echo "Warnings:         ${YLW}${warnings}${DEF}"
echo

# Exit status
if [[ $failed -gt 0 ]]; then
  echo "${RED}❌ Validation failed!${DEF}"
  exit 1
else
  echo "${GRN}✅ All scripts passed syntax validation!${DEF}"
  if [[ $warnings -gt 0 ]]; then
    echo "${YLW}⚠  Some scripts have linter warnings${DEF}"
  fi
  exit 0
fi
