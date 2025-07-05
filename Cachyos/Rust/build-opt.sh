#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'  

export LANG=C LC_ALL=C

# Toolchains
export CC="clang" CXX="clang++" CPP="clang-cpp"
export AR="llvm-ar" NM="llvm-nm" RANLIB="llvm-ranlib"
export STRIP="llvm-strip"
export RUSTC_BOOTSTRAP=1 RUSTUP_TOOLCHAIN=nightly RUST_BACKTRACE=full
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
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C lto=on -C relro-level=off -C debuginfo=0 -C strip=symbols -C debuginfo=0 -C force-frame-pointers=no -C link-dead-code=no \
-Z tune-cpu=native -Z default-visibility=hidden  -Z location-detail=none -Z function-sections"
# -C embed-bitcode=yes -Z dylib-lto

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

