#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

export LC_ALL=C LANG=C
shopt -s nullglob globstar

# Clean up cargo cache on exit
trap 'cargo-cache -efg' EXIT

# —————————————————————————————————————————————————————
# Defaults & help
USE_MOLD=0
LOCKED_FLAG=""
CRATE=""

usage() {
  cat <<EOF >&2
Usage: $0 [-mold] [--locked] <crate>

  -mold       use mold as the linker
  --locked    pass --locked to cargo install
  <crate>     name of the crate to install
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
export CARGO_INCREMENTAL=0 CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
export CARGO_HTTP_SSL_VERSION=tlsv1.3 CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse

# ensure RUSTFLAGS is set
: "${RUSTFLAGS:=}"

if ((USE_MOLD)); then
  if command -v mold >/dev/null 2>&1; then
    echo "→ using ld.mold via clang"
    LFLAGS=" -C linker=clang -C link-arg=-fuse-ld=mold"
    CLDFLAGS="-fuse-ld=mold"
  elif command -v clang >/dev/null 2>&1; then
    echo "→ using ld.lld via clang"
    LFLAGS=" -C linker=clang -C link-arg=-fuse-ld=lld"
    CLDFLAGS="-fuse-ld=lld"
  fi
fi

# —————————————————————————————————————————————————————
# Core optimization flags
export CFLAGS="-march=native -mtune=native -O3 -pipe -pthread -fdata-sections -ffunction-sections -Wno-error"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-gc-sections -Wl,-s -Wl,--icf=all ${CLDFLAGS}"
RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat -Cembed-bitcode=yes -Ztune-cpu=native \
-Cdebuginfo=0 -Crelro-level=off -Zdefault-visibility=hidden -Zdylib-lto -Cforce-frame-pointers=no -Zfunction-sections -Zthreads=${jobs}"
ZFLAGS="-Z unstable-options -Z fewer-names -Z combine-cgu -Z merge-functions=aliases"
EXTRA="-C link-arg=-s -C link-arg=-Wl,--icf=all -C link-arg=-Wl,--gc-sections"
export RUSTFLAGS="${RUSTFLAGS} ${LFLAGS} ${ZFLAGS} ${EXTRA}"

# Additional flags for cargo install
INSTALL_FLAGS="-Z unstable-options -Z git -Z gitoxide -Z no-embed-metadata"

# —————————————————————————————————————————————————————
# Finally, install the crate
echo "Installing '$CRATE' with optimized flags…"
cargo +nightly "${INSTALL_FLAGS}" install "$CRATE" ${LOCKED_FLAG} --jobs ${jobs} &&
  LANG=C.UTF-8 echo "🎉 $CRATE successfully installed in '$HOME/.cargo/bin'"
exit 0
