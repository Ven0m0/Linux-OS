#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

# usage check
if [ $# -lt 1 ]; then
  echo "Usage: $0 <crate-name> [--locked]"
  exit 1
fi

# 2) Look for --locked among the rest
locked_flag=""
for arg in "$@"; do
  if [ "$arg" = "--locked" ]; then
    locked_flag="--locked"
    break
  fi
done

cd "$HOME"

export RUSTUP_TOOLCHAIN=nightly # for nightly flags
export RUSTC_BOOTSTRAP=1 # Allow experimental features
export RUST_BACKTRACE="full" # Tracing

if command -v sccache >/dev/null 2>&1; then
  export RUSTC_WRAPPER=sccache
fi


# Set optimization flags and build
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C strip=symbols -C lto=on -C embed-bitcode=yes -Z dylib-lto -C relro-level=off -Z tune-cpu=native \
-Z default-visibility=hidden -Z fmt-debug=none -Z location-detail=none -C debuginfo=0 \
-C prefer-inline "
# -Z build-std=std,panic_abort
export CFLAGS="-march=native -mtune=native -O3 -pipe -fno-plt -Wno-error \
   	-mharden-sls=none -fcf-protection=none -fno-semantic-interposition -fdata-sections -ffunction-sections \
	-mprefer-vector-width=256 -ftree-vectorize -fslp-vectorize \
	-fomit-frame-pointer -fvisibility=hidden -fmerge-all-constants -finline-functions \
	-fbasic-block-sections=all -fjump-tables -fshort-enums -fshort-wchar \
	-pthread -falign-functions=32 -falign-loops=32 -malign-branch-boundary=32 -malign-branch=jcc"
export CXXFLAGS="$CFLAGS -fsized-deallocation -fstrict-vtable-pointers -fno-rtti -fno-exceptions -Wp,-D_GLIBCXX_ASSERTIONS"
export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now \
         -Wl,-z,pack-relative-relocs -Wl,-gc-sections -Wl,--compress-relocations \
         -Wl,--discard-locals -Wl,--strip-all -Wl,--icf=all"
export STRIP="llvm-strip -s -U"

cargo +nightly install "$1" $locked_flag \
  -Z unstable-options \
  -Z gc \
  -Z feature-unification \
  -Z no-embed-metadata \
  -Z avoid-dev-deps
