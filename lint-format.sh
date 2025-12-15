#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'

script=${BASH_SOURCE[0]}
[[ $script != /* ]] && script=$PWD/$script
cd -P -- "${script%/*}"

usage() {
  cat <<'EOF'
Usage: ./lint-format.sh [-c|--check]
  -c, --check   Run in check mode (no writes)
  -h, --help    Show this help
EOF
}

has() { command -v -- "$1" &>/dev/null; }

check_mode=0
status=0

while (($#)); do
  case "$1" in
    -c | --check) check_mode=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

fd_cmd=${FD:-}
if [[ -n $fd_cmd ]]; then
  has "$fd_cmd" || fd_cmd=""
fi
if [[ -z $fd_cmd ]]; then
  if has fdfind; then
    fd_cmd=fdfind
  elif has fd; then
    fd_cmd=fd
  fi
fi

if [[ -n $fd_cmd ]]; then
  mapfile -t shell_files < <(
    "$fd_cmd" --hidden --exclude .git --exclude .github/agents -e sh -e bash
  )
else
  mapfile -t shell_files < <(
    find . \( -path './.git' -o -path './.github/agents' \) -prune -o -type f \( -name '*.sh' -o -name '*.bash' \) -print
  )
fi

if has shfmt && ((${#shell_files[@]})); then
  if ((check_mode)); then
    if ! diff_out=$(shfmt -i 2 -bn -ci -s -ln bash -d "${shell_files[@]}"); then
      status=1
    fi
    if [[ -n ${diff_out:-} ]]; then
      printf '%s\n' "$diff_out"
      status=1
    fi
  else
    shfmt -i 2 -bn -ci -s -ln bash -w "${shell_files[@]}" || status=1
  fi
fi

if has shellcheck && ((${#shell_files[@]})); then
  shellcheck --severity=error "${shell_files[@]}" || status=1
fi

exit $status
