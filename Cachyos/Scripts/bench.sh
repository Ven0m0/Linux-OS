#!/usr/bin/env bash
# Unified benchmark script for parallel commands, sorting, and file copy operations
# Refactored: 2025-12-04 - Extracted common helpers to lib/core.sh and lib/browser.sh

# Source common libraries
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/../../lib/core.sh" || exit 1
# shellcheck source=lib/browser.sh
source "${SCRIPT_DIR}/../../lib/browser.sh" || exit 1

# Override HOME for SUDO_USER context
export HOME="/home/${SUDO_USER:-$USER}"

# Initialize privilege tool

# Usage information
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Unified benchmark script for testing parallel commands, sorting, and file copy operations.

Options:
  -p, --parallel    Run parallel command benchmarks (xargs, parallel, rust-parallel, etc.)
  -s, --sort        Run sort benchmarks with different thread counts
  -c, --copy        Run file copy benchmarks (cp, cpz, xcp, uu-cp, cpui)
  -a, --all         Run all benchmarks (default)
  -j, --json        Export results to JSON/JSONL format
  -h, --help        Show this help message

Examples:
  $0                Run all benchmarks
  $0 -p             Run only parallel command benchmarks
  $0 -s -c          Run sort and copy benchmarks
  $0 -a -j          Run all benchmarks and export to JSON

Note: hyperfine must be installed to run benchmarks.
EOF
  exit 0
}

# Parse command line arguments
RUN_PARALLEL=0
RUN_SORT=0
RUN_COPY=0
EXPORT_JSON=0

if [[ $# -eq 0 ]]; then
  RUN_PARALLEL=1
  RUN_SORT=1
  RUN_COPY=0 # Copy requires specific test files
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    -p | --parallel)
      RUN_PARALLEL=1
      shift
      ;;
    -s | --sort)
      RUN_SORT=1
      shift
      ;;
    -c | --copy)
      RUN_COPY=1
      shift
      ;;
    -a | --all)
      RUN_PARALLEL=1
      RUN_SORT=1
      RUN_COPY=1
      shift
      ;;
    -j | --json)
      EXPORT_JSON=1
      shift
      ;;
    -h | --help) usage ;;
    *)
      log "${RED}Unknown option: $1${DEF}"
      usage
      ;;
  esac
done

# Check for hyperfine
has hyperfine || die "hyperfine not found in PATH. Please install it first."

# Cache nproc result to avoid repeated calls
nproc_count="$(nproc 2> /dev/null || echo 1)"
jobs16="$nproc_count"
jobs8="$((nproc_count / 2))"
((jobs8 < 1)) && jobs8=1

# Save original turbo state
if [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
  o1="$(< /sys/devices/system/cpu/intel_pstate/no_turbo)"
  Reset() {
    echo "$o1" | sudo tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &> /dev/null || :
  }
  # Set performance mode
  sudo cpupower frequency-set --governor performance &> /dev/null || :
  echo 1 | sudo tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &> /dev/null || :
else
  Reset() { :; }
  sudo cpupower frequency-set --governor performance &> /dev/null || :
fi

# Benchmark function for parallel/sort tests
benchmark() {
  local name="$1"
  shift
  local cmd="$*"
  log "${BLU}▶${DEF} $name"
  command hyperfine -w 25 -m 50 -i -S bash \
    -p "sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null; resolvectl flush-caches &>/dev/null || :; hash -r" \
    "$cmd"
}

# Benchmark function for copy tests with JSON export
benchmark_copy() {
  local name="$1"
  shift
  local cmd="$*"

  log "${BLU}▶${DEF} $name"

  if [[ $EXPORT_JSON -eq 1 ]]; then
    hyperfine \
      --warmup 5 \
      --prepare "sudo fstrim -a --quiet-unsupported &>/dev/null; sudo journalctl --vacuum-time=1s &>/dev/null; sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null" \
      --export-json /tmp/hf-"$name".json \
      "$cmd"

    if [[ -f /tmp/hf-"$name".json ]]; then
      jq -c '{cmd: .command, mean: .results[0].mean, stddev: .results[0].stddev}' \
        /tmp/hf-"$name".json >> "$LOG"
      rm -f /tmp/hf-"$name".json
    fi
  else
    hyperfine \
      --warmup 5 \
      --prepare "sudo fstrim -a --quiet-unsupported &>/dev/null; sudo journalctl --vacuum-time=1s &>/dev/null; sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null" \
      "$cmd"
  fi
}

# Initialize JSON log if needed
if [[ $EXPORT_JSON -eq 1 ]]; then
  LOG="bench-results-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
  : > "$LOG" # Truncate file using : as no-op command
  log "${GRN}Results will be exported to: $LOG${DEF}"
fi

# Run parallel command benchmarks
if [[ $RUN_PARALLEL -eq 1 ]]; then
  log ""
  log "${BWHT}=== Parallel Command Benchmarks ===${DEF}"
  log ""

  has xargs && benchmark "xargs" "seq 1000 | xargs -n1 -P$nproc_count echo" || log "${YLW}⊘ xargs not available${DEF}"
  has parallel && benchmark "parallel" "seq 1000 | parallel -j $nproc_count echo {}" || log "${YLW}⊘ parallel not available${DEF}"
  has rust-parallel && benchmark "rust-parallel" "seq 1000 | rust-parallel -j $nproc_count echo {}" || log "${YLW}⊘ rust-parallel not available${DEF}"
  has parel && benchmark "parel" "parel -t $nproc_count 'seq 1000'" || log "${YLW}⊘ parel not available${DEF}"
  has parallel-sh && benchmark "parallel-sh" "parallel-sh -j $nproc_count 'seq 1000'" || log "${YLW}⊘ parallel-sh not available${DEF}"
fi

# Run sort benchmarks
if [[ $RUN_SORT -eq 1 ]]; then
  log ""
  log "${BWHT}=== Sort Benchmarks ===${DEF}"
  log ""

  benchmark "sort-$jobs16-threads" "sort -u -s --parallel=\"$jobs16\" -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-$jobs8-threads" "sort -u -s --parallel=\"$jobs8\" -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-4-threads" "sort -u -s --parallel=4 -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-2-threads" "sort -u -s --parallel=2 -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-1-thread" "sort -u -s -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-default" "sort -u /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
fi

# Run copy benchmarks
if [[ $RUN_COPY -eq 1 ]]; then
  log ""
  log "${BWHT}=== File Copy Benchmarks ===${DEF}"
  log ""

  # Check if test file exists
  if [[ ! -f cachyos.iso ]]; then
    log "${YLW}Warning: cachyos.iso not found in current directory${DEF}"
    log "${YLW}Copy benchmarks require a test file named 'cachyos.iso'${DEF}"
    log "${YLW}Skipping copy benchmarks...${DEF}"
  else
    has cp && benchmark_copy "cp" "cp cachyos.iso cachyos-cp.iso --no-preserve=all -x -f" || log "${YLW}⊘ cp not available${DEF}"
    has cpz && benchmark_copy "cpz" "cpz cachyos.iso cachyos-cpz.iso -f" || log "${YLW}⊘ cpz not available${DEF}"

    if has xcp; then
      benchmark_copy "xcp-w0" "xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w 0"
      benchmark_copy "xcp-w4" "xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms"
      benchmark_copy "xcp-w8" "xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w8"
      benchmark_copy "xcp-w0-2MB-block" "xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w 0 --block-size 2MB"
    else
      log "${YLW}⊘ xcp not available${DEF}"
    fi

    has uu-cp && benchmark_copy "uu-cp" "uu-cp -f --no-preserve=all cachyos.iso cachyos-uu-cp.iso" || log "${YLW}⊘ uu-cp not available${DEF}"
    has cpui && benchmark_copy "cpui" "cpui -f -y cachyos.iso cachyos-cpui.iso" || log "${YLW}⊘ cpui not available${DEF}"

    # Cleanup test files
    rm -f cachyos-*.iso &> /dev/null || :
  fi
fi

log ""
log "${GRN}✅ Benchmarks complete${DEF}"

if [[ $EXPORT_JSON -eq 1 && -f $LOG ]]; then
  log "${GRN}Results saved to: $LOG${DEF}"
fi

Reset
