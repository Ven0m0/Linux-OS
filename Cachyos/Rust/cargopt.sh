#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

cd "$HOME"

export RUST_BACKTRACE="full"


# Set optimization flags and build
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C strip=symbols -C lto=on -C embed-bitcode=yes -Z dylib-lto -C relro-level=off -Z tune-cpu=native \
-Z default-visibility=hidden -Z fmt-debug=none -Z location-detail=none"

export CFLAGS="-march=native -mtune=native -O3 -pipe -fno-plt -Wno-error \
  -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security -mharden-sls=none \
  -fstack-clash-protection -fcf-protection=none -fno-semantic-interposition -fdata-sections -ffunction-sections \
	-mprefer-vector-width=256 -ftree-vectorize -fslp-vectorize \
	-fomit-frame-pointer -fvisibility=hidden -fmerge-all-constants -finline-functions \
	-fbasic-block-sections=all -fjump-tables \
	-pthread -falign-functions=32 -falign-loops=32 -malign-branch-boundary=32 -malign-branch=jcc \
	-fshort-enums -fshort-wchar -feliminate-unused-debug-types -feliminate-unused-debug-symbols"
export CXXFLAGS="$CFLAGS -fsized-deallocation -fstrict-vtable-pointers -fno-rtti -fno-exceptions -Wp,-D_GLIBCXX_ASSERTIONS"
export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now \
         -Wl,-z,pack-relative-relocs -Wl,-gc-sections -Wl,--compress-relocations \
         -Wl,--discard-locals -Wl,--strip-all -Wl,--icf=all"
export STRIP="llvm-strip -s --disable-deterministic-archives"
export STRIP="strip -s --disable-deterministic-archives"

cargo +nightly build --release \
  -Z unstable-options \
  -Z gc \
  -Z feature-unification \
  -Z no-embed-metadata \
  -Z avoid-dev-deps
