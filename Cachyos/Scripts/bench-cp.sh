#!/usr/bin/bash
set -euo pipefail
sudo -v

LOG="copy-bench-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
> "$LOG"

benchmark() {
  local name="$1"; shift
  local cmd="$*"

  hyperfine \
    --warmup 5 \
    --prepare "sudo fstrim -a --quiet-unsupported; sudo journalctl --vacuum-time=1s; sudo sync" \
    --export-json /tmp/hf-"$name".json \
    "$cmd"

  jq -c '{cmd: .command, mean: .results.mean, stddev: .results.stddev}' \
    /tmp/hf-"$name".json >> "$LOG"
  rm -f /tmp/hf-"$name".json
}

benchmark "cp"    cp cachyos.iso cachyos-cp.iso --no-preserve=all -x -f
benchmark "cpz"   cpz cachyos.iso cachyos-cpz.iso -f
benchmark "xcp-w0"   xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w 0
benchmark "xcp-w4"   xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms
benchmark "xcp-w8"   xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w8
benchmark "xcp-w0-2MB-block"   xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w 0 --block-size 2MB
benchmark "uu-cp" uu-cp -f --no-preserve=all cachyos.iso cachyos-uu-cp.iso

echo "✅ Benchmarks complete. Results in $LOG"
