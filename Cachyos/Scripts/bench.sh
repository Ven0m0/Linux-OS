#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C

#–– Helper to test for a binary in $PATH
have() { command -v "$1" &>/dev/null; }
suexec="$(command -v sudo-rs 2>/dev/null || command -v sudo 2>/dev/null || command -v doas 2>/dev/null)"
[[ $suexec == */sudo-rs || $suexec == */sudo ]] && "$suexec" -v || :
have hyperfine || { echo "❌ hyperfine not found in PATH"; exit 1; }

o1="$(< /sys/devices/system/cpu/intel_pstate/no_turbo)"
Reset() { 
  "$suexec" sh -c "echo $o1 > /sys/devices/system/cpu/intel_pstate/no_turbo"
}
"$suexec" cpupower frequency-set --governor performance &>/dev/null || :
"$suexec" sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo" &>/dev/null || :

benchmark() {
  local name="$1"; shift
  local cmd="$*"
  echo "▶ $name"
  hyperfine -w 5 -m 20 -i \
    -p "sync; $suexec sh -c 'echo 3 > /proc/sys/vm/drop_caches'" \
    "$cmd"
}

# Benchmarks
benchmark "xargs" "seq 1000 | xargs -n1 -P$(nproc) echo"
benchmark "parallel" "seq 1000 | parallel -j $(nproc) echo {}"
benchmark "rust-parallel" "seq 1000 | rust-parallel -j $(nproc) echo {}"
benchmark "parel" "parel -t $(nproc) 'seq 1000'"
benchmark "parallel-sh" "parallel-sh -j $(nproc) 'seq 1000'"

echo "✅ Benchmarks complete..."
Reset
