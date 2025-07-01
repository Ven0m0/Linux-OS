#!/usr/bin/bash
set -euo pipefail
sudo -v

export LANG=C
export LC_ALL=C

benchmark() {
  local name="$1"; shift
  local cmd="$*" # Join all remaining args into one string

  echo "▶ Running benchmark: $name"
  hyperfine \
    --warmup 5 \
    -i \
    --prepare "sudo fstrim -a --quiet-unsupported; sudo journalctl --vacuum-time=1s; sync; echo 3 | sudo tee /proc/sys/vm/drop_caches" \
    "$cmd"
}

# Template
#benchmark "" ""

benchmark "xargs" "seq 1000 | xargs -n1 -P$(nproc) echo"
benchmark "parallel" "seq 1000 | parallel -j $(nproc) echo {}"
benchmark "rust-parallel" "seq 1000 | rust-parallel -j $(nproc) echo {}"

echo "✅ Benchmarks complete..."
