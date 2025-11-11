#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || exit 1

# Shell Script Optimizer
# A utility to format, harden, lint, and minify shell scripts.
# It can operate on a single file or recursively on a directory.
# Dependencies: shfmt, shellharden, shellcheck, awk, sd (optional)
#
usage(){
  cat <<EOF
Usage: ${0##*/} [-f] [-m] [-s] [-h] <file_or_dir>

Applies formatting, hardening, and linting to shell scripts.

Options:
  -r, --recursive   Process directory recursively. Required if target is a directory.
  -f, --format      Apply shfmt formatting (default).
  -m, --minify      Minify code with shfmt (implies -f).
  -s, --strip       Strip all comments and copyright headers.
  -h, --help        Show this help message.
EOF
  exit 1
}

# arg parsing
declare -a files
recursive=0
format=1
minify=0
strip=0
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--recursive) recursive=1; shift ;;
    -f|--format) format=1; shift ;;
    -m|--minify) minify=1; format=1; shift ;;
    -s|--strip) strip=1; shift ;;
    -h|--help) usage ;;
    -*) printf "Unknown option: %s\n" "$1"; usage ;;
    *) break ;;
  esac
done

target="${1:?No file or directory specified.}"

# check dependencies
for cmd in shfmt shellharden shellcheck awk; do
  has "$cmd" || die "Error: '$cmd' is not installed."
done
readonly HAS_SD=$(has sd && echo 1 || echo 0)

# collect files
if [[ -d "$target" ]]; then
  (( recursive == 0 )) && die "Error: Use -r for directories."
  mapfile -d '' files < <(find "$target" -type f \( -name '*.sh' -o -name '*.bash' \) -print0)
else
  [[ -f "$target" ]] && files=("$target") || die "Error: File not found: $target"
fi
(( ${#files[@]} == 0 )) && { log "No shell scripts found."; exit 0; }

# awk script for stripping comments and headers
read -r -d '' awk_script <<'AWK'
# Strip shebang, then process. Preserve initial empty lines if not header.
NR == 1 && /^#!/ { print; next }
# Strip copyright headers (contiguous '#' lines at start).
!header_done && /^#/ { next }
# Once a non-header line is found, stop header processing.
!header_done { header_done = 1 }
# Strip full-line comments, ignore lines with code then comment.
/^[[:space:]]*#/ { next }
# Strip trailing inline comments (basic version).
{ sub(/[[:space:]]+#.*/, ""); print }
AWK

optimize_file(){
  local file="$1"
  local content
  content=$(<"$file")

  # 1. Strip comments and headers
  if (( strip == 1 )); then
    content=$(printf '%s' "$content" | awk "$awk_script")
  fi

  # 2. Normalize bashisms
  if (( HAS_SD == 1 )); then
    content=$(sd '\|\| true' '|| :' <<<"$content")
    content=$(sd '\s*\(\)\s*\{' '(){' <<<"$content")
    content=$(sd '>\/dev\/null 2>&1' '&>/dev/null' <<<"$content")
  else
    content=$(sed -e 's/|| true/|| :/g' -e 's/[[:space:]]*()[[:space:]]*{/(){/g' -e 's|>/dev/null 2>&1|\&>/dev/null|g' <<<"$content")
  fi

  # 3. Format/Minify
  if (( format == 1 )); then
    local -a shfmt_opts=(-ln bash -bn -i 2 -s)
    (( minify == 1 )) && shfmt_opts+=(-mn)
    content=$(shfmt "${shfmt_opts[@]}" <<<"$content")
  fi
  
  # Write changes before running tools that modify in-place
  printf '%s' "$content" > "$file"

  # 4. Harden & Lint (in-place)
  shellharden --replace "$file" &>/dev/null || :
  shellcheck -a -x -s bash --source-path=SCRIPTDIR -f diff "$file" | patch -p1 "$file" &>/dev/null || :

  printf "Optimized: %s\n" "$file"
}

for file in "${files[@]}"; do
  optimize_file "$file"
done

printf "Done. Processed %d file(s).\n" "${#files[@]}"
