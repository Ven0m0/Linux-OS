#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                            CONFIGURATION                              │
# └─────────────────────────────────────────────────────────────────────────┘

# Project directory (assumes Cargo.toml is here)
# Posix compatible
#WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Non-posix
WORKDIR="$(readlink -f -- "${BASH_SOURCE[0]%/*}")"
cd "$WORKDIR"

# Use nightly Rust for LLVM args and PGO support
RUST_TOOLCHAIN=nightly

# Common RUSTFLAGS for everything
COMMON_RUSTFLAGS="
  -C opt-level=3
  -C target-cpu=native
  -C lto=fat
  -C codegen-units=1
  -C embed-bitcode=yes
"

# “Hidden” LLVM passes to enable via -Cllvm-args
# — aggressive jump threading, scheduling, GVN, loop transforms…
LLVM_HIDDEN_FLAGS=(
  -enable-dfa-jump-thread
  -enable-misched
  -enable-gvn-hoist
  -enable-gvn-sink
  -enable-loopinterchange
  -enable-pipeliner
  -enable-tail-merge
  -polly
  -polly-vectorizer
  -polly-tiling
)

# Helper to join flags into “-Cllvm-args=flag1 -Cllvm-args=flag2 …”
function llvm_args() {
  for f in "${LLVM_HIDDEN_FLAGS[@]}"; do
    printf -- "--llvm-args=%s " "$f"
  done
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                             PHASE 1: PGO                         │
# └─────────────────────────────────────────────────────────────────────────┘

echo "=== [1/5] Building instrumentation-enabled binary (PGO generate) ==="

export RUSTFLAGS="
  $COMMON_RUSTFLAGS
  -Cprofile-generate=./pgo_data
  $(llvm_args)
"

cargo +"$RUST_TOOLCHAIN" clean
cargo +"$RUST_TOOLCHAIN" build --release

echo "Run your workload to generate profiles:"
echo "  ./target/release/your_binary $@"
echo "When done, press ENTER to continue…"
read -r

echo "Merging raw profiles into one profdata…"
llvm-profdata merge -output=default.profdata ./pgo_data

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                            PHASE 2: PGO Use                         │
# └─────────────────────────────────────────────────────────────────────────┘

echo "=== [2/5] Building PGO-optimized binary (PGO use) ==="

export RUSTFLAGS="
  $COMMON_RUSTFLAGS
  -Cprofile-use=./default.profdata
  -Cprofile-remap-dir=./pgo_data  # fix paths if needed
  $(llvm_args)
"

cargo +"$RUST_TOOLCHAIN" clean
cargo +"$RUST_TOOLCHAIN" build --release

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                         PHASE 3: AutoFDO (Sample)                  │
# └─────────────────────────────────────────────────────────────────────────┘

echo "=== [3/5] Running sample-based profiling (perf + llvm-profdata) ==="

# Run under Linux ‘perf record’ to collect sample profile
perf record -F 99 -a -g -- ./target/release/your_binary "$@"
# Convert perf.data → sample.profdata
llvm-profdata merge -sample-profile=perf.data -output=sample.profdata

echo "=== [4/5] Building sample-FDO-optimized binary ==="

export RUSTFLAGS="
  $COMMON_RUSTFLAGS
  -Cllvm-args=-fprofile-sample-use=sample.profdata
  -Cllvm-args=-fprofile-sample-use-threshold=1
  $(llvm_args)
"

cargo +"$RUST_TOOLCHAIN" clean
cargo +"$RUST_TOOLCHAIN" build --release

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                             PHASE 4: BOLT                              │
# └─────────────────────────────────────────────────────────────────────────┘

echo "=== [5/5] Running BOLT to layout hot paths ==="

# Path to the FDO-optimized binary
BIN=./target/release/your_binary
BOLT_BIN=./target/release/your_binary.bolt

# Instrumented BOLT run to produce a profile
perf record -e cycles:u -j any,u -- $BIN "$@"
# Re-optimize the binary layout
llvm-bolt \
  $BIN \
  --use-profile=perf.data \
  --reorder-blocks=ext-tsp \
  --split-functions \
  --split-all-cold \
  --icf=1 \
  --layout=hottext \
  --output=$BOLT_BIN

echo "=== Done! ==="
echo "Final optimized executable: $BOLT_BIN"
