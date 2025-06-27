#!/usr/bin/bash
set -euo pipefail
sudo -v

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

benchmark "du" "du -sh $HOME 2>/dev/null || true"
benchmark "dust" "dust -c -b -P -T 16 --skip-total $HOME 2>/dev/null || true"

echo "✅ Benchmarks complete..."
