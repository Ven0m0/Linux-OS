#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
IFS=$'\n\t'

cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && echo "${PWD:-$(pwd)}")"

#–– Helpers
has() { command -v "$1" &>/dev/null; }

# Fully safe optimal privelege tool
suexec="$(command -v sudo-rs 2>/dev/null || command -v sudo 2>/dev/null || command -v doas 2>/dev/null || :)"
[[ "${suexec:-}" == */sudo-rs || "${suexec:-}" == */sudo ]] && "$suexec" -v || :
suexec="${suexec:-sudo}"
if ! command -v "$suexec" &>/dev/null; then
  echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2
  exit 1
fi


dirname(){
  # Usage: dirname "path"
  local tmp=${1:-.}
  [[ $tmp != *[!/]* ]] && { printf '/\n'; return; }
  tmp=${tmp%%"${tmp##*[!/]}"}
  [[ $tmp != */* ]] && { printf '.\n'; return; }
  tmp=${tmp%/*}
  tmp=${tmp%%"${tmp##*[!/]}"}
  printf '%s\n' "${tmp:-/}"
}
basename(){
  # Usage: basename "path" ["suffix"]
  local tmp
  tmp=${1%"${1##*[!/]}"}
  tmp=${tmp##*/}
  tmp=${tmp%"${2/"$tmp"}"}
  printf '%s\n' "${tmp:-/}" 
}
regex() {
    # Usage: regex "string" "regex"
    [[ $1 =~ $2 ]] && printf '%s\n' "${BASH_REMATCH[1]}"
}

