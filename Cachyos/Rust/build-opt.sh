#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
# —————————————————————————————————————————————————————
# Presetup
LC_ALL=C LANG=C.UTF-8
hash -r
hash  cargo rustc  nproc sccache cat sudo
sync
sudo -v
rustup update
# Save originals
orig_kptr=$(cat /proc/sys/kernel/kptr_restrict)
orig_perf=$(sysctl -n kernel.perf_event_paranoid)
orig_turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)

# —————————————————————————————————————————————————————
# Clean up cargo cache on error
cleanup() {
  trap - ERR HUP TERM INT ABRT
  cargo-cache -efg >/dev/null 2>&1 || true
  cargo clean >/dev/null 2>&1 || true
  rm -rf "$HOME/.cache/sccache/"* >/dev/null 2>&1 || true
}
trap cleanup ERR HUP TERM INT ABRT
# —————————————————————————————————————————————————————
# Defaults & help
USE_MOLD=0
PGO_MODE=0    # 0: no PGO, 1: profile generation, 2: profile use
USE_BOLT=0

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -pgo)
      shift
      if [[ "$1" =~ ^[0-2]$ ]]; then
        PGO_MODE="$1"
      else
        echo "Error: -pgo requires 0, 1, or 2"
        exit 1
      fi
      ;;
    -bolt)
      USE_BOLT=1
      ;;
    --)
      shift
      CARGO_ARGS+=("$@")
      break
      ;;
    *)
      CARGO_ARGS+=("$1")
      ;;
  esac
  shift || break
  # stop parsing after --
done

# Ensure cargo-pgo is installed
if ! command -v cargo-pgo >/dev/null; then
  echo "cargo-pgo not found, installing..."
  cargo install cargo-pgo
fi
# —————————————————————————————————————————————————————
# Toolchains
#export CC="clang" CXX="clang++" CPP="clang-cpp"
export AR="llvm-ar" NM="llvm-nm" RANLIB="llvm-ranlib"
export STRIP="llvm-strip"
export RUSTC_BOOTSTRAP=1 
#RUSTUP_TOOLCHAIN=nightly RUST_BACKTRACE=full
export CARGO_INCREMENTAL=0 CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
export CARGO_HTTP_SSL_VERSION=tlsv1.3 CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse

ZFLAGS="-Z unstable-options -Z gc -Z git -Z gitoxide -Z avoid-dev-deps -Z feature-unification"
LTOFLAGS="-C lto=on -C embed-bitcode=yes -Z dylib-lto"
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C relro-level=off \
	-Z tune-cpu=native -Z fmt-debug=none -Z location-detail=none -Z default-visibility=hidden ${LTOFLAGS} ${ZFLAGS}"
# Parallel codegen frontend (no perf loss)
export RUSTFLAGS="${RUSTFLAGS} -Z threads=16"
# Parse options
git_update=false
opts=$(getopt -o g --long git -n 'cbuild.sh' -- "$@")
eval set -- "$opts"
while true; do
  case "$1" in
    -g|--git)
      git_update=true; shift ;;
    --)
      shift; break ;;
    *)
      echo "Usage: $0 [-g|--git]"; exit 1 ;;
  esac
done

# Ensure cargo-pgo is installed
if ! command -v cargo-pgo >/dev/null; then
  echo "cargo-pgo not found, installing..."
  cargo install cargo-pgo
fi

# Optionally update repo
if [ "$git_update" = true ]; then
  git pull --rebase
fi

# Git
git reflog expire --expire=now --all &&
git gc --prune=now --aggressive &&
git repack -a -d --depth=250 --window=250 --write-bitmap-index
git clean -fdX

# Update and fix code
cargo update --recursive
cargo upgrade --recursive true
cargo fix --workspace --all-targets --all-features -r --bins --allow-dirty
cargo clippy --fix --workspace --all-targets --all-features --allow-dirty --allow-staged
cargo fmt --all

# Install missing tools if needed
for tool in cargo-shear cargo-machete cargo-cache ; do
  command -v "$tool" >/dev/null || cargo install "$tool"
done

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
# -C embed-bitcode=yes -Z dylib-lto

# Execute build based on PGO_MODE
case "$PGO_MODE" in
  0)
    echo "[PGO] running standard release build"
    cargo build --release "${CARGO_ARGS[@]}"
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
  # determine binary name and path via cargo metadata
  metadata_json=$(cargo metadata --format-version 1 --no-deps)
  target_dir=$(jq -r '.target_directory' <<< "$metadata_json")
  bin_name=$(jq -r '.packages[0].name' <<< "$metadata_json")
  bin_path="$target_dir/release/$bin_name"

  if [[ ! -f "$bin_path" ]]; then
    echo "Error: binary not found at $bin_path"
    exit 1
  fi

  echo "[BOLT] optimizing $bin_name with llvm-bolt"
  # Merge profraw files if present
  profraw_dir="$target_dir/release/pgo"
  if [[ -d "$profraw_dir" && -n $(ls -A "$profraw_dir"/*.profraw 2>/dev/null) ]]; then
    llvm-profdata merge -o merged.profdata "$profraw_dir"/*.profraw
    llvm-bolt "$bin_path" -data=merged.profdata -o "$bin_path.bolt"
  else
    llvm-bolt "$bin_path" -o "$bin_path.bolt"
  fi
  echo "[BOLT] output written to $bin_path.bolt"
fi

cargo +nightly ${NIGHTLYFLAGS} build --release

### Rustflags for pgo:
### in /.cargp/config.toml
### [target.x86_64-unknown-linux-gnu]
### rustflags = ""
### 
### export RUSTFLAGS="-Z debug-info-for-profiling"
### Mold:
### linker = "mold"
### export RUSTFLAGS="-C linker=mold"
### -fuse-ld=mold
### export LD=mold

# Disable perf sudo requirement
sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid"
perf record -e cycles:u --call-graph dwarf -o pgo.data -- ./target/.../binary
perf record -e cycles:u -j any,u --call-graph dwarf -o pgo.data -- ./target/.../binary

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

