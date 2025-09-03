#!/usr/bin/env bash
export LC_ALL=C LANG=C; shopt -s nullglob

#–– Helper to test for a binary in $PATH
has() { command -v -- "$1" &>/dev/null; } # Check for command
hasname(){ local x=$(type -P -- "$1") && printf '%s\n' "${x##*/}"; }
xecho() { printf '%s\n' "$@" 2>/dev/null; } # Print-echo
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v 2>/dev/null || :
export HOME="/home/${SUDO_USER:-$USER}"
has hyperfine || { echo "❌ hyperfine not found in PATH"; exit 1; }

o1="$(</sys/devices/system/cpu/intel_pstate/no_turbo)"
Reset(){ 
  #echo "${o1:-0}" | sudo tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &>/dev/null || :
  echo 0 | "$suexec" tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &>/dev/null || :
}
"$suexec" cpupower frequency-set --governor performance &>/dev/null || :
echo 1 | "$suexec" tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &>/dev/null || :

benchmark(){
  local name="$1"; shift
  local cmd="$*"
  xprintf "▶ $name"
  command hyperfine -w 25 -m 50 -i -S bash \
    -p "sync; echo 3 | doas tee /proc/sys/vm/drop_caches &>/dev/null; resolvectl flush-caches; hash -r" \
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
