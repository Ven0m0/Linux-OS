#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd $WORKDIR

file="${1:-}"

[[ -z $file ]] && {
  echo "Please supply a script name to create"
  exit 1
}
[[ -f $file ]] && {
  echo "${file} already exists, aborting"
  exit 1
}

mkdir -p "$WORKDIR/${file}"

cat >"${file}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C LANG=C.UTF-8
WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd $WORKDIR

EOF

chmod +x "${file}"
