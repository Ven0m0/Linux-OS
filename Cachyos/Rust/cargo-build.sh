#!/usr/bin/env bash
# Unified Rust Cargo Build Script with PGO/BOLT optimization support
# Combines features from cargopt.sh, test.sh, build-script1.sh, and build-opt.sh

set -eEuo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar inherit_errexit
export LC_ALL=C LANG=C

# ──────────────────────────────────────────────────────────────────────────────
# Cleanup trap
# ──────────────────────────────────────────────────────────────────────────────
cleanup(){
  trap - ERR EXIT HUP QUIT TERM INT ABRT
  set +e
  command -v cargo-cache &>/dev/null && cargo-cache -efg &>/dev/null
  cargo clean &>/dev/null || :
  command -v cargo-pgo &>/dev/null && cargo pgo clean &>/dev/null || :
  rm -rf "$HOME/.cache/sccache/"* &>/dev/null || :
  set -e
}
trap cleanup ERR EXIT HUP QUIT TERM INT ABRT

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
MODE="build" # build, install, pgo, bolt
PGO_LEVEL=0  # 0=off, 1=instrument, 2=optimize
BOLT_ENABLED=0
GIT_CLEANUP=0
USE_MOLD=0
LOCKED_FLAG=""
DEBUG_MODE=0
CRATES=()
BUILD_ARGS=()

# ──────────────────────────────────────────────────────────────────────────────
# Usage
# ──────────────────────────────────────────────────────────────────────────────
usage(){
  cat << EOF
Usage: $0 [OPTIONS] [<crate>...]

Unified Rust build script with advanced optimizations including PGO and BOLT.

Modes:
  -b, --build         Build project (default)
  -i, --install       Install crate(s) from crates.io
  --pgo <0|1|2>       PGO mode: 0=off, 1=instrument, 2=optimize
  --bolt              Enable BOLT optimization (requires PGO)

Options:
  -m, --mold          Use mold linker
  -l, --locked        Pass --locked to cargo
  -g, --git           Run git cleanup first
  -d, --debug         Enable debug mode (verbose output)
  -h, --help          Show this help message

Build Arguments:
  --                  Pass remaining args to cargo command

Examples:
  # Install crates with optimizations
  $0 --install ripgrep fd bat

  # Build with PGO instrumentation
  $0 --pgo 1

  # Build with PGO optimization
  $0 --pgo 2

  # Build with PGO + BOLT
  $0 --pgo 2 --bolt

  # Install with mold linker and locked dependencies
  $0 --install --mold --locked eza

  # Build with git cleanup
  $0 --build --git
EOF
  exit "${1:-0}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage 1

while [[ $# -gt 0 ]]; do
  case $1 in
    -b | --build)
      MODE="build"
      shift
      ;;
    -i | --install)
      MODE="install"
      shift
      ;;
    --pgo)
      shift
      [[ $1 =~ ^[0-2]$ ]] || {
        echo "Error: --pgo requires 0, 1, or 2">&2
        exit 1
      }
      PGO_LEVEL=$1
      MODE="pgo"
      shift
      ;;
    --bolt)
      BOLT_ENABLED=1
      shift
      ;;
    -m | --mold)
      USE_MOLD=1
      shift
      ;;
    -l | --locked)
      LOCKED_FLAG="--locked"
      shift
      ;;
    -g | --git)
      GIT_CLEANUP=1
      shift
      ;;
    -d | --debug)
      DEBUG_MODE=1
      set -x
      export RUST_LOG=trace RUST_BACKTRACE=1
      shift
      ;;
    -h | --help) usage 0 ;;
    --)
      shift
      BUILD_ARGS=("$@")
      break
      ;;
    -*)
      echo "Error: unknown option '$1'">&2
      usage 1
      ;;
    *)
      CRATES+=("$1")
      shift
      ;;
  esac
done

# Validate options
if [[ $MODE == "install" && ${#CRATES[@]} -eq 0 ]]; then
  echo "Error: install mode requires at least one crate">&2
  usage 1
fi

if [[ $BOLT_ENABLED -eq 1 && $PGO_LEVEL -ne 2 ]]; then
  echo "Error: BOLT requires --pgo 2">&2
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# System setup
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Setting up build environment..."

# Validate privileges if needed
if [[ $EUID -ne 0 ]]; then
  sudo -v || {
    echo "Error: sudo failed">&2
    exit 1
  }
fi

# CPU performance mode
sudo cpupower frequency-set --governor performance &>/dev/null || :

# Update Rust if requested
if [[ $MODE == "install" ]]; then
  read -r -p "Update Rust toolchains? [y/N] " ans
  [[ $ans =~ ^[Yy]$ ]] && rustup update &>/dev/null || :
fi

# Git cleanup
if [[ $GIT_CLEANUP -eq 1 ]] && git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "==> Running git cleanup..."
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive
  git repack -ad --depth=250 --window=250
  git clean -fdX
fi

# Install required tools
for tool in cargo-shear cargo-machete cargo-cache; do
  command -v "$tool" &>/dev/null || cargo install "$tool"
done

if [[ $MODE == "pgo" || $BOLT_ENABLED -eq 1 ]]; then
  command -v cargo-pgo &>/dev/null || {
    rustup component add llvm-tools-preview
    cargo install cargo-pgo
  }
fi

# ──────────────────────────────────────────────────────────────────────────────
# Environment setup
# ──────────────────────────────────────────────────────────────────────────────
jobs=$(nproc 2>/dev/null || echo 4)

# Compiler setup
if command -v sccache &>/dev/null; then
  export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache
  export SCCACHE_DIRECT=true SCCACHE_RECACHE=true SCCACHE_IDLE_TIMEOUT=10800
  sccache --start-server &>/dev/null || :
else
  export CC=clang CXX=clang++
  unset RUSTC_WRAPPER
fi

export CPP=clang-cpp AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib STRIP=llvm-strip
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER

# Cargo configuration
export CARGO_CACHE_RUSTC_INFO=1
export CARGO_FUTURE_INCOMPAT_REPORT_FREQUENCY=never
export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
export CARGO_HTTP_MULTIPLEXING=true
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export CARGO_HTTP_SSL_VERSION="tlsv1.3"
export CARGO_INCREMENTAL=0
export RUSTC_BOOTSTRAP=1
export RUSTUP_TOOLCHAIN=nightly
export CARGO_BUILD_JOBS="$jobs"
export CARGO_PROFILE_RELEASE_LTO=true
export OPT_LEVEL=3

# Memory allocator configuration
export MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
export _RJEM_MALLOC_CONF="$MALLOC_CONF"
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled &>/dev/null || :

# Linker flags
LFLAGS=()
CLDFLAGS=()
if [[ $USE_MOLD -eq 1 ]]; then
  LFLAGS+=(-Clink-arg=-fuse-ld=mold)
  CLDFLAGS+=(-fuse-ld=mold)
elif command -v ld.lld &>/dev/null; then
  LFLAGS+=(-Clink-arg=-fuse-ld=lld)
  CLDFLAGS+=(-fuse-ld=lld)
fi

# CFLAGS/LDFLAGS
CFLAGS="-march=native -mtune=native -O3 -pipe -pthread -fdata-sections -ffunction-sections -fno-semantic-interposition"
CXXFLAGS="$CFLAGS"
# shellcheck disable=SC2054  # Commas in -Wl flags are not array separators
LDFLAGS=(
  -Wl,-O3
  -Wl,--sort-common
  -Wl,--as-needed
  -Wl,-gc-sections
  -Wl,-s
  -Wl,-z,now
  -Wl,-z,relro
  -Wl,--icf=all
  -Wl,-z,pack-relative-relocs
  -flto
  "${CLDFLAGS[@]}"
)

# Base RUSTFLAGS
RUSTFLAGS_BASE=(
  -Copt-level=3
  -Ctarget-cpu=native
  -Ccodegen-units=1
  -Cstrip=symbols
  -Clto=fat
  -Clinker-plugin-lto
  -Ztune-cpu=native
  -Cdebuginfo=0
  -Cpanic=abort
  -Crelro-level=off
  -Zdefault-visibility=hidden
  -Zdylib-lto
  -Cforce-frame-pointers=n
  -Clink-dead-code=n
  -Zfunction-sections
  -Zlocation-detail=none
  -Zfmt-debug=none
  -Zthreads=8
  -Zrelax-elf-relocations
  -Zpacked-bundled-libs
  -Ztrap-unreachable=no
)

# Additional link args
# shellcheck disable=SC2054  # Commas in -Wl flags are not array separators
EXTRA_LINK=(
  -Clink-arg=-Wl,-O3
  -Clink-arg=-Wl,-gc-sections
  -Clink-arg=-Wl,--icf=all
  -Clink-arg=-Wl,--sort-common
  -Clink-arg=-Wl,--as-needed
  -Clink-arg=-Wl,-z,now
  -Clink-arg=-Wl,--lto-O3
)

# Unstable flags
ZFLAGS=(
  -Zunstable-options
  -Zfewer-names
  -Zcombine-cgu
  -Zmerge-functions=aliases
  -Zno-embed-metadata
  -Zmir-opt-level=3
  -Zchecksum-hash-algorithm=blake3
  -Zprecise-enum-drop-elaboration=yes
)

# Combine all RUSTFLAGS
export RUSTFLAGS="${RUSTFLAGS_BASE[*]} ${LFLAGS[*]} ${ZFLAGS[*]} ${EXTRA_LINK[*]}"
export CFLAGS="$CFLAGS"
export CXXFLAGS="$CXXFLAGS"
# shellcheck disable=SC2178  # Intentionally converting array to string for export
export LDFLAGS="${LDFLAGS[*]}"

# Additional cargo install flags
INSTALL_FLAGS=(-Zunstable-options -Zgit -Zgitoxide -Zno-embed-metadata)
MISC_OPT=(--ignore-rust-version -f --bins -j"$jobs")

# ──────────────────────────────────────────────────────────────────────────────
# Profile configuration helper functions
# ──────────────────────────────────────────────────────────────────────────────
profileon(){
  echo "==> Enabling profiling mode..."
  sudo sh -c "echo 0>/proc/sys/kernel/randomize_va_space" || :
  sudo sh -c "echo 0>/proc/sys/kernel/nmi_watchdog" || :
  sudo sh -c "echo 1>/sys/devices/system/cpu/intel_pstate/no_turbo" || :
  sudo sh -c "echo 0>/proc/sys/kernel/kptr_restrict" || :
  sudo sh -c "echo 0>/proc/sys/kernel/perf_event_paranoid" || :
}

profileoff(){
  echo "==> Disabling profiling mode..."
  sudo sh -c "echo 1>/proc/sys/kernel/randomize_va_space" || :
  sudo sh -c "echo 0>/sys/devices/system/cpu/intel_pstate/no_turbo" || :
}

# ──────────────────────────────────────────────────────────────────────────────
# Main execution
# ──────────────────────────────────────────────────────────────────────────────

case $MODE in
  build)
    echo "==> Building project..."

    # Project maintenance
    if git rev-parse --is-inside-work-tree &>/dev/null; then
      cargo update --recursive &>/dev/null || :
      cargo fix --workspace --all-targets --allow-dirty -r &>/dev/null || :
      cargo clippy --fix --workspace --allow-dirty &>/dev/null || :
      cargo fmt &>/dev/null || :
      command -v cargo-shear &>/dev/null && cargo-shear --fix &>/dev/null || :
      command -v cargo-machete &>/dev/null && cargo-machete --fix &>/dev/null || :
    fi

    cargo-cache -g -f -e clean-unref &>/dev/null || :
    cargo +nightly build --release "${BUILD_ARGS[@]}"
    echo "✅ Build complete"
    ;;

  install)
    echo "==> Installing crates: ${CRATES[*]}"

    sync
    for crate in "${CRATES[@]}"; do
      echo "→ Installing $crate..."
      cargo +nightly "${INSTALL_FLAGS[@]}" install "$LOCKED_FLAG" "${MISC_OPT[@]}" "$crate"
      echo "✅ $crate installed in $HOME/.cargo/bin"
    done
    ;;

  pgo)
    echo "==> Building with PGO (level: $PGO_LEVEL)..."

    if [[ $PGO_LEVEL -eq 1 ]]; then
      # Instrumentation phase
      profileon
      cargo pgo clean
      cargo clean

      export RUSTFLAGS="${RUSTFLAGS} -Cprofile-generate=./pgo_data -Cembed-bitcode=yes"
      cargo +nightly pgo build --release "${BUILD_ARGS[@]}"

      echo ""
      echo "==> Instrumentation build complete"
      echo "Run your workload to generate profiles:"
      echo "  ./target/release/<binary> <args>"
      echo ""
      echo "Then merge profiles with:"
      echo "  llvm-profdata merge -output=default.profdata ./pgo_data"
      echo ""
      echo "After that, run with --pgo 2 to build optimized binary"

    elif [[ $PGO_LEVEL -eq 2 ]]; then
      # Optimization phase
      profileon

      if [[ ! -f default.profdata ]]; then
        echo "Error: default.profdata not found. Run --pgo 1 first and generate profiles.">&2
        exit 1
      fi

      if [[ $BOLT_ENABLED -eq 1 ]]; then
        export RUSTFLAGS="${RUSTFLAGS} -Cembed-bitcode=yes -Clink-args=-Wl,--emit-relocs"
      else
        export RUSTFLAGS="${RUSTFLAGS} -Cembed-bitcode=yes"
      fi

      export RUSTFLAGS="${RUSTFLAGS} -Cprofile-use=./default.profdata -Cprofile-correction -Cllvm-args=-pgo-warn-missing-function"

      cargo pgo clean
      cargo clean
      cargo +nightly pgo build --release "${BUILD_ARGS[@]}"

      if [[ $BOLT_ENABLED -eq 1 ]]; then
        echo "==> Running BOLT optimization..."
        cargo pgo bolt build --with-pgo

        echo ""
        echo "==> Run your workload with the BOLT instrumented binary:"
        echo "  ./target/release/<binary>-bolt-instrumented <args>"
        echo ""
        echo "Then run to create final optimized binary:"
        echo "  cargo pgo bolt optimize --with-pgo"
      fi

      profileoff
      echo "✅ PGO optimization complete"
    fi
    ;;
esac

echo ""
echo "✅ All operations complete"
