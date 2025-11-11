#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || exit 1

# Override HOME for SUDO_USER context
export HOME="/home/${SUDO_USER:-$USER}"

# Initialize privilege tool
PRIV_CMD=$(init_priv)

hasname() { local x=$(type -P -- "$1") && printf '%s\n' "${x##*/}"; }
has hyperfine || {
  echo "❌ hyperfine not found in PATH"
  exit 1
}

# Cache nproc result to avoid repeated calls
nproc_count="$(nproc 2>/dev/null || echo 1)"
jobs16="$nproc_count"
jobs8="$((nproc_count / 2))"
((jobs8 < 1)) && jobs8=1

o1="$(</sys/devices/system/cpu/intel_pstate/no_turbo)"
Reset() {
  echo 0 | run_priv tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &>/dev/null || :
}
run_priv cpupower frequency-set --governor performance &>/dev/null || :
echo 1 | run_priv tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &>/dev/null || :

benchmark() {
  local name="$1"
  shift
  local cmd="$*"
  printf '%s\n' "▶ $name"
  command hyperfine -w 25 -m 50 -i -S bash \
    -p "sync; echo 3 | ${PRIV_CMD:-sudo} tee /proc/sys/vm/drop_caches &>/dev/null; resolvectl flush-caches; hash -r" \
    "$cmd"
}
# Benchmarks
benchmark "xargs" "seq 1000 | xargs -n1 -P$nproc_count echo"
benchmark "parallel" "seq 1000 | parallel -j $nproc_count echo {}"
benchmark "rust-parallel" "seq 1000 | rust-parallel -j $nproc_count echo {}"
benchmark "parel" "parel -t $nproc_count 'seq 1000'"
benchmark "parallel-sh" "parallel-sh -j $nproc_count 'seq 1000'"
benchmark "sort 16" "sort -u -s --parallel=\"$jobs16\" -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
benchmark "sort 8" "sort -u -s --parallel=\"$jobs8\" -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
benchmark "sort 4" "sort -u -s --parallel=4 -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
benchmark "sort 2" "sort -u -s --parallel=2 -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
benchmark "sort 1" "sort -u -s -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
benchmark "sort" "sort -u /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"

echo "✅ Benchmarks complete..."
Reset
