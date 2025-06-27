#!/usr/bin/env bash
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

# Update and fix code
cargo update --recursive
cargo fix --workspace --all-targets --all-features -r --bins --allow-dirty
cargo clippy --fix --workspace --all-targets --all-features --allow-dirty --allow-staged

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
export RUSTFLAGS='-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C strip=symbols -C lto=on -C embed-bitcode=yes -Z dylib-lto \
-Z tune-cpu=native -Z default-visibility=hidden -Z fmt-debug=none -Z location-detail=none -C relro-level=off'

cargo +nightly build --release \
  -Z unstable-options \
  -Z gc \
  -Z feature-unification \
  -Z no-embed-metadata \
  -Z avoid-dev-deps
