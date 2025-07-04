#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'  

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

# Optionally update repo
if [ "$git_update" = true ]; then
  git pull --rebase
fi

export RUSTUP_TOOLCHAIN=nightly # for nightly flags
export RUSTC_BOOTSTRAP=1 # Allow experimental features
export RUST_BACKTRACE="full" # Tracing

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

# -Z bindeps

cargo +nightly build --release \
  -Z unstable-options \
  -Z gc \
  -Z feature-unification \
  -Z no-embed-metadata \
  -Z avoid-dev-deps \
  -Z git \
  -Z gitoxide \
  -Z trim-paths"
