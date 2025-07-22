#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
set -CE
# —————————————————————————————————————————————————————
# Speed and caching
LC_ALL=C LANG=C.UTF-8
hash -r
hash cargo rustc clang git nproc sccache cat sudo
sudo cpupower frequency-set --governor performance
# —————————————————————————————————————————————————————
# Preparation
sudo -v
read -r -p "Update Rust toolchains? [y/N] " ans
[[ $ans =~ ^[Yy]$ ]] && rustup update >/dev/null 2>&1 || true
# Save originals
orig_kptr=$(cat /proc/sys/kernel/kptr_restrict)
orig_perf=$(cat /proc/sys/kernel/perf_event_paranoid)
orig_turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)
orig_thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled)

# —————————————————————————————————————————————————————
# Install missing tools if needed
for tool in cargo-pgo cargo-shear cargo-machete cargo-cache ; do
  command -v "$tool" >/dev/null || cargo install "$tool" || true
done
# —————————————————————————————————————————————————————
# Clean up cargo cache on error
cleanup() {
  trap - ERR EXIT HUP QUIT TERM INT ABRT
  set +e
  cargo-cache -efg >/dev/null 2>&1 || true
  cargo clean >/dev/null 2>&1 || true
  rm -rf "$HOME/.cache/sccache/"* >/dev/null 2>&1 || true
  # restore kernel settings
  echo "$orig_kptr" | sudo tee /proc/sys/kernel/kptr_restrict >/dev/null || true
  echo "$orig_perf" | sudo tee /proc/sys/kernel/perf_event_paranoid >/dev/null || true
  echo "$orig_turbo" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null || true
  echo "$orig_thp" | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null || true
  set -e
}
trap cleanup ERR EXIT HUP QUIT TERM INT ABRT
# —————————————————————————————————————————————————————
# Defaults & help
USE_MOLD=0
PGO_MODE=0    # 0: no PGO, 1: profile generation, 2: profile use
USE_BOLT=0
CARGO_ARGS=()
GIT=0

# Parse options
# Parse args
while (($#)); do
    -pgo)
      shift
      if [[ "$1" =~ ^[0-2]$ ]]; then
        PGO_MODE="$1"
      else
        echo "Error: -pgo requires 0, 1, or 2"; exit 1
      fi ;;
    -bolt)
      USE_BOLT=1; shift ;;
    --)
      CARGO_ARGS+=("$@"); break ;;
    *)
      CARGO_ARGS+=("$1") ;;
  esac
  shift || break
  # stop parsing after --
done

# —————————————————————————————————————————————————————
# Prepare environment
jobs="$(nproc)"
cd "$HOME"

# https://github.com/rust-lang/rust/blob/master/src/ci/run.sh
# Use sccache if installed
if command -v sccache >/dev/null 2>&1; then
  export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache
  SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server 2>/dev/null || true
else
  export CC="clang" CXX="clang++"
  unset RUSTC_WRAPPER
fi
export CPP="clang-cpp"
export AR="llvm-ar" NM="llvm-nm" RANLIB="llvm-ranlib"
export STRIP="llvm-strip"
# Make sure rustflags arent being overwritten by cargo
unset CARGO_ENCODED_RUSTFLAGS
# Cargo settings/tweaks
export CARGO_CACHE_RUSTC_INFO=1 
export CARGO_HTTP_SSL_VERSION="tlsv1.3" CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
export CARGO_INCREMENTAL=0
export RUSTC_BOOTSTRAP=1
export CARGO_PROFILE_RELEASE_LTO=true
export CARGO_BUILD_JOBS="$jobs"
export CARGO_FUTURE_INCOMPAT_REPORT_FREQUENCY=never CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
# export RUSTUP_TOOLCHAIN=nightly
# RUST_LOG=trace
export MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
export _RJEM_MALLOC_CONF="$MALLOC_CONF"
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null || true

# ensure RUSTFLAGS is set
: "${RUSTFLAGS:=}"

if ((USE_MOLD)); then
  if command -v mold >/dev/null 2>&1; then
    echo "→ using ld.mold via clang"
    LFLAGS=(-Clinker=clang -Clink-arg=-fuse-ld=mold)
    CLDFLAGS=(-fuse-ld=mold)
    hash mold
  elif command -v clang >/dev/null 2>&1; then
    echo "→ using ld.lld via clang"
    LFLAGS=(-Clinker=clang -Clink-arg=-fuse-ld=lld -Clinker-features=lld)
    CLDFLAGS=(-fuse-ld=lld)
    hash lld ld.lld
  else
    echo "→ falling back to ld.lld via linker-flavor"
    LFLAGS=(-Clinker-flavor=ld.lld -C linker-features=lld)
    CLDFLAGS=(-fuse-ld=lld)
  fi
fi

# —————————————————————————————————————————————————————
# Git
git reflog expire --expire=now --all &&
git gc --prune=now --aggressive
git repack -a -d --depth=250 --window=250 --write-bitmap-index
git clean -fdX

# Update and fix code
cargo update --recursive
cargo upgrade --recursive true
cargo fix --workspace --all-targets --all-features -r --bins --allow-dirty
cargo clippy --fix --workspace --all-targets --all-features --allow-dirty --allow-staged
cargo fmt --all

# Clean and debloat
cargo +nightly udeps
cargo-shear --fix
cargo-machete --fix --with-metadata
cargo-cache -g -f -e clean-unref

# General flags
# Default build
export NIGHTLYFLAGS="-Z unstable-options -Z gc -Z git -Z gitoxide"
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C lto=on -C embed-bitcode=yes -C relro-level=off -C debuginfo=0 -C strip=symbols -C debuginfo=0 -C force-frame-pointers=no -C link-dead-code=no \
-Z tune-cpu=native -Z default-visibility=hidden  -Z location-detail=none -Z function-sections"

# Disable perf sudo requirement
sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid"
#perf record -e cycles:u --call-graph dwarf -o pgo.data -- ./target/.../binary
#perf record -e cycles:u -j any,u --call-graph dwarf -o pgo.data -- ./target/.../binary
# PGO
#-Z build-std=std,panic_abort
#-Z build-std-features=panic_immediate_abort
#PGO 2nd compilation:
#-C profile-correction
#-Cllvm-args=-pgo-warn-missing-function -Cprofile-use
### Rustflags for pgo:
### export RUSTFLAGS="-Z debug-info-for-profiling -C link-args=-Wl,--emit-relocs"
# -Z profile-sample-use 

# Profile accuracy
profileon () {
    echo "Performance profiling on"
    sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space" || (sudo sysctl -w kernel.randomize_va_space=0)
    sudo sh -c "echo 0 > /proc/sys/kernel/nmi_watchdog" || (sudo sysctl -w kernel.nmi_watchdog=0)
    sudo sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo"
    sudo cpupower frequency-set --governor performance
}
profileoff () {
    echo "Performance profiling off"
    sudo sh -c "echo 1 > /proc/sys/kernel/randomize_va_space"
    sudo sh -c "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo"
}
profileon
# Execute build based on PGO_MODE
case "$PGO_MODE" in
  0)
    echo "[PGO] running standard release build"
    cargo pgo build
    ;;
  1)
    echo "[PGO] generating instrumentation profiles..."
    cargo pgo instr build --release "${CARGO_ARGS[@]}"
    echo "[PGO] instrumentation complete. Run your binary under target/release to collect .profraw files."
    exit 0
    ;;
  2)
    echo "[PGO] building using collected profiles..."
    cargo pgo opt build --release "${CARGO_ARGS[@]}"
    ;;
  *)
    echo "Invalid PGO mode: $PGO_MODE. Use -pgo 0, 1, or 2."
    exit 1
    ;;
esac

# If BOLT requested, apply it to the produced binary
if [[ "$USE_BOLT" -eq 1 ]]; then
  # Build BOLT instrumented binary using PGO profiles
  cargo pgo bolt build --with-pgo
  # Run binary to gather BOLT profiles
  ./target/.../<binary>-bolt-instrumented
  # Optimize a PGO-optimized binary with BOLT
  cargo pgo bolt optimize --with-pgo
fi
profileoff
cargo +nightly ${NIGHTLYFLAGS} build --release

# Build PGO instrumented binary
cargo pgo build
# Run binary to gather PGO profiles
#hyperfine "/target/.../binary"
cargo +nightly ${NIGHTLYFLAGS} run --bin "/target/.../binary" -r
./target/.../<binary>
# Build BOLT instrumented binary using PGO profiles
cargo pgo bolt build --with-pgo
# Run binary to gather BOLT profiles
./target/.../<binary>-bolt-instrumented
# Optimize a PGO-optimized binary with BOLT
cargo pgo bolt optimize --with-pgo
export LastBuild="-C strip=symbols"

