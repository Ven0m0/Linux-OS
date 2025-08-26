#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C

#–– Helper to test for a binary in $PATH
has() { command -v -- "$1" &>/dev/null; } # Check for command
hasname(){ local x; x=$(type -P -- "$1") || return; printf '%s\n' "${x##*/}"; } # Get basename of command
p() { printf '%s\n' "$@" 2>/dev/null; } # Print-echo
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { p "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v || :
has hyperfine || { echo "❌ hyperfine not found in PATH"; exit 1; }

o1="$(< /sys/devices/system/cpu/intel_pstate/no_turbo)"
Reset() { 
  "$suexec" sh -c 'echo "${o1:-0}" >/sys/devices/system/cpu/intel_pstate/no_turbo' &>/dev/null
}
"$suexec" cpupower frequency-set --governor performance &>/dev/null || :
"$suexec" sh -c 'echo 1 >/sys/devices/system/cpu/intel_pstate/no_turbo' &>/dev/null || :

benchmark() {
  local name="$1"; shift
  local cmd="$*"
  p "▶ $name"
  hyperfine -w 25 -m 50 -i -S bash \
    -p "sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; systemd-resolve --flush-caches; hash -r" \
    "$cmd"
}

# Benchmarks
benchmark "xargs" "seq 1000 | xargs -n1 -P$(nproc) echo"
benchmark "parallel" "seq 1000 | parallel -j $(nproc) echo {}"
benchmark "rust-parallel" "seq 1000 | rust-parallel -j $(nproc) echo {}"
benchmark "parel" "parel -t $(nproc) 'seq 1000'"
benchmark "parallel-sh" "parallel-sh -j $(nproc) 'seq 1000'"

p "✅ Benchmarks complete..."
Reset
