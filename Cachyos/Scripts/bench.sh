#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8

#–– Helper to test for a binary in $PATH
have() { command -v "$1" >/dev/null 2>&1; }

if have "sudo-rs"; then
  suexec="sudo-rs"
  sudo-rs -v || true
elif have "/usr/bin/sudo"; then
  suexec="/usr/bin/sudo"
  /usr/bin/sudo -v || true
elif have "sudo"; then
  suexec="sudo"
  sudo -v || true
else
  suexec="doas"
fi

export LANG=C
export LC_ALL=C

benchmark() {
  local name="$1"; shift
  local cmd="$*" # Join all remaining args into one string

  echo "▶ Running benchmark: $name"
  hyperfine \
    -w 5 \
    -i \
    --prepare "sync; echo 3 | $suexec tee /proc/sys/vm/drop_caches" \
    "$cmd"
}

# Template
#benchmark "" ""
benchmark "xargs" "seq 1000 | xargs -n1 -P$(nproc) echo"
benchmark "parallel" "seq 1000 | parallel -j $(nproc) echo {}"
benchmark "rust-parallel" "seq 1000 | rust-parallel -j $(nproc) echo {}"
benchmark "parel" "parel -t $(nproc) 'seq 1000'"
benchmark "parallel-sh" "parallel-sh -j $(nproc) 'seq 1000'"

echo "✅ Benchmarks complete..."
