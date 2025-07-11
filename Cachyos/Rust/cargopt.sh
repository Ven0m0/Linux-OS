#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

export LC_ALL=C LANG=C
shopt -s nullglob globstar

# https://kobzol.github.io/rust/rustc/2023/10/21/make-rust-compiler-5percent-faster.html
export MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,background_thread:true,percpu_arena:percpu"
export _RJEM_MALLOC_CONF="${MALLOC_CONF}"
# tcache_max:4096

# Clean up cargo cache on error
cleanup() {
  cargo-cache -efg >/dev/null 2>&1 || true  
  cargo clean >/dev/null 2>&1 || true
}
trap cleanup ERR EXIT

# —————————————————————————————————————————————————————
# Defaults & help
USE_MOLD=0
LOCKED_FLAG=""
CRATE=""

usage() {
  cat <<EOF >&2
Usage: $0 [-mold] [--locked] <crate> [-h|--help]

  -mold       use mold as the linker
  --locked    pass --locked to cargo install
  <crate>     name of the crate to install
  -h,--help   display help
EOF
  exit 1
}

# —————————————————————————————————————————————————————
# Simple argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
  -mold)
    USE_MOLD=1
    shift
    ;;
  --locked)
    LOCKED_FLAG="--locked"
    shift
    ;;
  -h | --help) usage ;;
  *)
    if [ -z "$CRATE" ]; then
      CRATE="$1"
    fi
    shift
    ;;
  esac
done

[ -n "$CRATE" ] || {
  echo "Error: <crate> is required" >&2
  usage
}

# —————————————————————————————————————————————————————
# Prepare environment
jobs="$(nproc)"
cd "$HOME"

# Use sccache if installed
if command -v sccache >/dev/null 2>&1; then
  export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache
else
  export CC="clang" CXX="clang++"
  unset RUSTC_WRAPPER
fi

export STRIP="llvm-strip"
# Make sure rustflags arent being overwritten by cargo
unset CARGO_ENCODED_RUSTFLAGS

# Cargo settings/tweaks
export CARGO_INCREMENTAL=0 CARGO_PROFILE_RELEASE_LTO=fat
export CARGO_CACHE_RUSTC_INFO=1
export CARGO_HTTP_SSL_VERSION=tlsv1.3 CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
export RUSTC_BOOTSTRAP=1
# export RUSTUP_TOOLCHAIN=nightly
# RUST_LOG=trace

# ensure RUSTFLAGS is set
: "${RUSTFLAGS:=}"

if ((USE_MOLD)); then
  if command -v mold >/dev/null 2>&1; then
    echo "→ using ld.mold via clang"
    LFLAGS=(
      -C linker=clang
      -C link-arg=-fuse-ld=mold
    )
    CLDFLAGS=(-fuse-ld=mold)
  elif command -v clang >/dev/null 2>&1; then
    echo "→ using ld.lld via clang"
    LFLAGS=(
      -C linker=clang
      -C link-arg=-fuse-ld=lld
      -C linker-features=lld
      -C link-arg=-Wl,--ignore-function-address-equality
      -C link-arg=--compact-branches
    )
    CLDFLAGS=(-fuse-ld=lld)
  else
    echo "→ falling back to ld.lld via linker-flavor"
    LFLAGS=(-C linker-flavor=ld.lld -C linker-features=lld)
    CLDFLAGS=(-fuse-ld=lld)
  fi
fi

# —————————————————————————————————————————————————————
# Core optimization flags
CFLAGS=(-march=native -mtune=native -O3 -pipe -pthread -fdata-sections -ffunction-sections -Wno-error)
CXXFLAGS=("${CFLAGS[@]}")
LDFLAGS=(
  -Wl,-O3 
  -Wl,--sort-common
  -Wl,--as-needed
  -Wl,-gc-sections
  -Wl,-s
  -Wl,-z,now
  -Wl,-z,relro
  -Wl,--icf=all
  -Wl,--ignore-data-address-equality
  -Wl,--enable-new-dtags
  -Wl,--optimize-bb-jumps
  -Wl,-z,pack-relative-relocs
  -Wl,--compress-relocations
  -Wl,--compress-sections=zstd:3
  -Wl,--compress-debug-sections=zstd
  -Wl,--lto-O3
  -Wl,--lto-partitions=1
  -Wl,-plugin-opt=--fat-lto-objects
  -Wl,-plugin-opt=--lto-aa-pipeline
  -Wl,-plugin-opt=--lto-newpm-passes
  -flto
  "${CLDFLAGS[@]}"
)
# https://github.com/johnthagen/min-sized-rust
# # https://doc.rust-lang.org/rustc/codegen-options/index.html#embed-bitcode
# # "-C link-arg=-flto" needed for mold
# "-Z threads=8" https://nnethercote.github.io/perf-book/build-configuration.html#experimental-parallel-front-end
RUSTFLAGS_BASE=(
  -C opt-level=3
  -C target-cpu=native
  -C codegen-units=1
  -C strip=true
  -C lto=fat
  -C link-arg=-flto
  #-C embed-bitcode=y
  -C linker-plugin-lto
  -Z tune-cpu=native
  -C debuginfo=0
  -C panic=abort
  -C relro-level=off
  -Z default-visibility=hidden
  -Z dylib-lto
  -C force-frame-pointers=n
  #-C force-unwind-tables=n
  -C link-dead-code=n
  -Z function-sections
  -Z location-detail=none
  -Z fmt-debug=none
  -Z threads=8
)
EXTRA_LINK=(
  -C link-arg=-Wl,-O3
  -C link-arg=-Wl,-gc-sections
  -C link-arg=-Wl,--icf=all
  -C link-arg=-Wl,--sort-common
  -C link-arg=-Wl,--as-needed
  -C link-arg=-Wl,-z,relro
  -C link-arg=-Wl,-z,now
  -C link-arg=-Wl,--lto-O3
  -C link-arg=-Wl,--optimize-bb-jumps
  -C link-arg=-Wl,--strip-all
  -C link-arg=-Wl,--compress-sections=zstd:3
  -C link-arg=-Wl,--compress-relocations
  -C link-arg=-Wl,--compress-debug-sections=zstd
  -C link-arg=-Wl,-z,pack-relative-relocs
  # -C link-arg=--lto-emit-llvm
  -C link-arg=-Wl,-plugin-opt=--lto-aa-pipeline
  -C link-arg=-Wl,-plugin-opt=--lto-newpm-passes
  -C link-arg=-Wl,--lto-O3
  -C link-arg=-Wl,--lto-partitions=1
  -C link-arg=-Wl,-plugin-opt=--fat-lto-objects
)
ZFLAGS=(-Z unstable-options -Z fewer-names -Z combine-cgu -Z merge-functions=aliases)

# Combine all rustflags into one exported variable
export RUSTFLAGS="${RUSTFLAGS_BASE[@]} ${LFLAGS[@]} ${ZFLAGS[@]} ${EXTRA_LINK[@]}"
export CFLAGS="${CFLAGS[@]}"
export CXXFLAGS="${CXXFLAGS[@]}"
export LDFLAGS="${LDFLAGS[@]}"

# Additional flags for cargo install
INSTALL_FLAGS=(-Z unstable-options -Z git -Z gitoxide -Z no-embed-metadata)

# —————————————————————————————————————————————————————
# Finally, install the crate
echo "Installing '$CRATE' with optimized flags…"
cargo +nightly "${INSTALL_FLAGS[@]}" install "$CRATE" ${LOCKED_FLAG} --jobs ${jobs} &&
  LANG=C.UTF-8 echo "🎉 $CRATE successfully installed in '$HOME/.cargo/bin'"
exit 0
