#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
# Unified Rust build & optimization system: build, install, PGO/BOLT, workflow automation
# ──────────────────────────────────────────────────────────────────────────────
# Cleanup trap
# ──────────────────────────────────────────────────────────────────────────────
cleanup() {
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
MODE="build"
PGO_LEVEL=0
BOLT_ENABLED=0
GIT_CLEANUP=0
USE_MOLD=0
LOCKED_FLAG=""
DEBUG_MODE=0
SKIP_ASSETS=0
DRY_RUN=0
CRATES=()
BUILD_ARGS=()
# Helpers
has() { command -v "$1" &>/dev/null; }
run() { ((DRY_RUN)) && echo "[DRY] $*" || "$@"; }
# ──────────────────────────────────────────────────────────────────────────────
# Usage
# ──────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage: cargo-build.sh [MODE] [OPTIONS] [<crate>...]

Unified Rust build system: build, install, optimize, workflow automation.

Modes:
  -b, --build         Build project (default)
  -i, --install       Install crate(s) from crates.io
  -w, --workflow      Full optimization workflow (update, lint, minify, build)
  --pgo <0|1|2>       PGO: 0=off, 1=instrument, 2=optimize
  --bolt              BOLT optimization (requires --pgo 2)

Options:
  -m, --mold          Use mold linker
  -l, --locked        Pass --locked to cargo
  -g, --git           Git cleanup first
  -d, --debug         Debug mode (verbose)
  --skip-assets       Skip asset optimization (workflow mode)
  --dry-run           Show commands without running
  -h, --help          Show help

Build Args:
  --                  Pass remaining args to cargo

Examples:
  cargo-build.sh --install ripgrep fd bat
  cargo-build.sh --workflow --skip-assets
  cargo-build.sh --pgo 1
  cargo-build.sh --pgo 2 --bolt
  cargo-build.sh --build --mold --locked
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
    -w | --workflow)
      MODE="workflow"
      shift
      ;;
    --pgo)
      shift
      [[ $1 =~ ^[0-2]$ ]] || {
        echo "Error: --pgo requires 0, 1, or 2" >&2
        exit 1
      }
      PGO_LEVEL=$1 MODE="pgo"
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
      DEBUG_MODE=1 set -x
      export RUST_LOG=trace RUST_BACKTRACE=1
      shift
      ;;
    --skip-assets)
      SKIP_ASSETS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help) usage 0 ;;
    --)
      shift
      BUILD_ARGS=("$@")
      break
      ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      usage 1
      ;;
    *)
      CRATES+=("$1")
      shift
      ;;
  esac
done
# Validate
[[ $MODE == "install" && ${#CRATES[@]} -eq 0 ]] && {
  echo "Error: install requires crate(s)" >&2
  usage 1
}
[[ $BOLT_ENABLED -eq 1 && $PGO_LEVEL -ne 2 ]] && {
  echo "Error: BOLT requires --pgo 2" >&2
  exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# System setup
# ──────────────────────────────────────────────────────────────────────────────
setup_system() {
  echo "==> Setting up build environment..."
  [[ $EUID -ne 0 ]] && { sudo -v || {
    echo "Error: sudo failed" >&2
    exit 1
  }; }
  sudo cpupower frequency-set --governor performance &>/dev/null || :
  if [[ $MODE == "install" ]]; then
    read -r -p "Update Rust toolchains? [y/N] " ans
    [[ $ans =~ ^[Yy]$ ]] && rustup update &>/dev/null || :
  fi
  if [[ $GIT_CLEANUP -eq 1 ]] && git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "==> Git cleanup..."
    git reflog expire --expire=now --all
    git gc --prune=now --aggressive
    git repack -ad --depth=250 --window=250
    git clean -fdX
  fi
  for tool in cargo-shear cargo-machete cargo-cache; do
    has "$tool" || cargo install "$tool"
  done
  if [[ $MODE == "pgo" || $BOLT_ENABLED -eq 1 ]]; then
    has cargo-pgo || {
      rustup component add llvm-tools-preview
      cargo install cargo-pgo
    }
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Environment setup
# ──────────────────────────────────────────────────────────────────────────────
setup_env() {
  local jobs
  jobs=$(nproc 2>/dev/null || echo 4)
  if has sccache; then
    export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache
    export SCCACHE_DIRECT=true SCCACHE_RECACHE=true SCCACHE_IDLE_TIMEOUT=10800
    sccache --start-server &>/dev/null || :
  else
    export CC=clang CXX=clang++
    unset RUSTC_WRAPPER
  fi
  export CPP=clang-cpp AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib STRIP=llvm-strip
  unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER
  export CARGO_CACHE_RUSTC_INFO=1 CARGO_FUTURE_INCOMPAT_REPORT_FREQUENCY=never
  export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always CARGO_HTTP_MULTIPLEXING=true
  export CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_HTTP_SSL_VERSION="tlsv1.3"
  export CARGO_INCREMENTAL=0 RUSTC_BOOTSTRAP=1 RUSTUP_TOOLCHAIN=nightly
  export CARGO_BUILD_JOBS="$jobs" CARGO_PROFILE_RELEASE_LTO=true OPT_LEVEL=3
  export MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
  export _RJEM_MALLOC_CONF="$MALLOC_CONF"
  echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled &>/dev/null || :
  local -a lflags=() cldflags=()
  if [[ $USE_MOLD -eq 1 ]]; then
    lflags+=(-Clink-arg=-fuse-ld=mold)
    cldflags+=(-fuse-ld=mold)
  elif has ld.lld; then
    lflags+=(-Clink-arg=-fuse-ld=lld)
    cldflags+=(-fuse-ld=lld)
  fi
  local cflags="-march=native -mtune=native -O3 -pipe -pthread -fdata-sections -ffunction-sections -fno-semantic-interposition"
  local -a ldflags=(-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-gc-sections -Wl,-s -Wl,-z,now -Wl,-z,relro -Wl,--icf=all -Wl,-z,pack-relative-relocs -flto "${cldflags[@]}")
  local -a rustflags_base=(
    -Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat -Clinker-plugin-lto
    -Ztune-cpu=native -Cdebuginfo=0 -Cpanic=abort -Crelro-level=off -Zdefault-visibility=hidden
    -Zdylib-lto -Cforce-frame-pointers=n -Clink-dead-code=n -Zfunction-sections -Zlocation-detail=none
    -Zfmt-debug=none -Zthreads=8 -Zrelax-elf-relocations -Zpacked-bundled-libs -Ztrap-unreachable=no
  )
  local -a extra_link=(
    -Clink-arg=-Wl,-O3 -Clink-arg=-Wl,-gc-sections -Clink-arg=-Wl,--icf=all
    -Clink-arg=-Wl,--sort-common -Clink-arg=-Wl,--as-needed -Clink-arg=-Wl,-z,now -Clink-arg=-Wl,--lto-O3
  )
  local -a zflags=(
    -Zunstable-options -Zfewer-names -Zcombine-cgu -Zmerge-functions=aliases -Zno-embed-metadata
    -Zmir-opt-level=3 -Zchecksum-hash-algorithm=blake3 -Zprecise-enum-drop-elaboration=yes
  )

  export RUSTFLAGS="${rustflags_base[*]} ${lflags[*]} ${zflags[*]} ${extra_link[*]}"
  export CFLAGS="$cflags" CXXFLAGS="$cflags" LDFLAGS="${ldflags[*]}"
  export INSTALL_FLAGS=(-Zunstable-options -Zgit -Zgitoxide -Zno-embed-metadata)
  export MISC_OPT=(--ignore-rust-version -f --bins -j"$jobs")
}
# ──────────────────────────────────────────────────────────────────────────────
# Profile helpers
# ──────────────────────────────────────────────────────────────────────────────
profileon() {
  echo "==> Profiling mode ON"
  sudo sh -c "echo 0>/proc/sys/kernel/randomize_va_space" || :
  sudo sh -c "echo 0>/proc/sys/kernel/nmi_watchdog" || :
  sudo sh -c "echo 1>/sys/devices/system/cpu/intel_pstate/no_turbo" || :
  sudo sh -c "echo 0>/proc/sys/kernel/kptr_restrict" || :
  sudo sh -c "echo 0>/proc/sys/kernel/perf_event_paranoid" || :
}
profileoff() {
  echo "==> Profiling mode OFF"
  sudo sh -c "echo 1>/proc/sys/kernel/randomize_va_space" || :
  sudo sh -c "echo 0>/sys/devices/system/cpu/intel_pstate/no_turbo" || :
}

# ──────────────────────────────────────────────────────────────────────────────
# Asset optimization helpers
# ──────────────────────────────────────────────────────────────────────────────
optimize_assets() {
  [[ $SKIP_ASSETS -eq 1 ]] && return
  local fd_cmd="" nproc_val
  nproc_val=$(nproc 2>/dev/null || echo 4)
  has fd && fd_cmd="fd" || has fdfind && fd_cmd="fdfind"
  # HTML minification
  if has minhtml; then
    echo "==> Minifying HTML..."
    if [[ -n $fd_cmd ]]; then
      "$fd_cmd" -H -t f '\.html$' -print0 | xargs -0 -P"$nproc_val" -I{} sh -c 'minhtml -i "$1" -o "$1"' _ {}
    else
      find . -type f -name '*.html' -print0 | xargs -0 -P"$nproc_val" -I{} sh -c 'minhtml -i "$1" -o "$1"' _ {}
    fi
  fi
  # Image optimization
  if [[ -d assets ]]; then
    echo "==> Optimizing images..."
    if has oxipng; then
      if [[ -n $fd_cmd ]]; then
        "$fd_cmd" -t f '\.png$' assets -print0 | xargs -0 -P"$nproc_val" oxipng -o 4 -q
      else
        find assets -type f -name '*.png' -print0 | xargs -0 -P"$nproc_val" oxipng -o 4 -q
      fi
    fi
    if has jpegoptim; then
      if [[ -n $fd_cmd ]]; then
        "$fd_cmd" -t f '\.(jpg|jpeg)$' assets -print0 | xargs -0 -P"$nproc_val" jpegoptim --strip-all -q
      else
        find assets -type f \( -name '*.jpg' -o -name '*.jpeg' \) -print0 | xargs -0 -P"$nproc_val" jpegoptim --strip-all -q
      fi
    fi
  fi
  # Static asset compression
  has flaca && [[ -d static ]] && {
    echo "==> Compressing static..."
    run flaca compress ./static || :
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Main execution
# ──────────────────────────────────────────────────────────────────────────────
setup_system
setup_env
case $MODE in
  build)
    echo "==> Building project..."
    if git rev-parse --is-inside-work-tree &>/dev/null; then
      run cargo update --recursive &>/dev/null || :
      run cargo fix --workspace --all-targets --allow-dirty -r &>/dev/null || :
      run cargo clippy --fix --workspace --allow-dirty &>/dev/null || :
      run cargo fmt &>/dev/null || :
      has cargo-shear && run cargo-shear --fix &>/dev/null || :
      has cargo-machete && run cargo-machete --fix &>/dev/null || :
    fi
    run cargo-cache -g -f -e clean-unref &>/dev/null || :
    run cargo +nightly build --release "${BUILD_ARGS[@]}"
    echo "✅ Build complete"
    ;;
  install)
    echo "==> Installing: ${CRATES[*]}"
    sync
    for crate in "${CRATES[@]}"; do
      echo "→ $crate..."
      run cargo +nightly "${INSTALL_FLAGS[@]}" install "$LOCKED_FLAG" "${MISC_OPT[@]}" "$crate"
      echo "✅ $crate → $HOME/.cargo/bin"
    done
    ;;

  workflow)
    echo "==> Starting optimization workflow..."
    echo "→ Updating dependencies..."
    run cargo update
    has cargo-outdated && run cargo outdated || :
    echo "→ Formatting & linting..."
    run cargo fmt
    run cargo clippy -- -D warnings
    has cargo-udeps && {
      echo "→ Checking unused deps..."
      run cargo +nightly udeps --all-targets 2>/dev/null || :
    }
    has cargo-shear && run cargo shear || :
    has cargo-machete && {
      echo "→ Finding dead code..."
      run cargo machete || :
    }
    optimize_assets
    has cargo-diet && run cargo diet || :
    has cargo-unused-features && run cargo unused-features || :
    has cargo-duplicated-deps && run cargo duplicated-deps || :
    echo "→ Final format pass..."
    run cargo fmt
    run cargo clippy -- -D warnings
    echo "→ Building release..."
    run cargo build --release
    bin="target/release/${PWD##*/}"
    [[ -f $bin ]] && {
      echo "→ Stripping..."
      run strip "$bin"
      ls -lh "$bin"
    }
    echo "✅ Workflow complete"
    ;;
  pgo)
    echo "==> PGO build (level: $PGO_LEVEL)..."
    if [[ $PGO_LEVEL -eq 1 ]]; then
      profileon
      run cargo pgo clean
      run cargo clean
      export RUSTFLAGS="${RUSTFLAGS} -Cprofile-generate=./pgo_data -Cembed-bitcode=yes"
      run cargo +nightly pgo build --release "${BUILD_ARGS[@]}"
      echo ""
      echo "==> Instrumentation complete. Run workload:"
      echo "  ./target/release/<binary> <args>"
      echo "Then merge profiles:"
      echo "  llvm-profdata merge -output=default.profdata ./pgo_data"
      echo "Run with --pgo 2 to optimize"
    elif [[ $PGO_LEVEL -eq 2 ]]; then
      profileon
      [[ ! -f default.profdata ]] && {
        echo "Error: default.profdata missing. Run --pgo 1 first." >&2
        exit 1
      }
      if [[ $BOLT_ENABLED -eq 1 ]]; then
        export RUSTFLAGS="${RUSTFLAGS} -Cembed-bitcode=yes -Clink-args=-Wl,--emit-relocs"
      else
        export RUSTFLAGS="${RUSTFLAGS} -Cembed-bitcode=yes"
      fi
      export RUSTFLAGS="${RUSTFLAGS} -Cprofile-use=./default.profdata -Cprofile-correction -Cllvm-args=-pgo-warn-missing-function"
      run cargo pgo clean
      run cargo clean
      run cargo +nightly pgo build --release "${BUILD_ARGS[@]}"
      if [[ $BOLT_ENABLED -eq 1 ]]; then
        echo "==> BOLT optimization..."
        run cargo pgo bolt build --with-pgo
        echo ""
        echo "==> Run workload with BOLT instrumented binary:"
        echo "  ./target/release/<binary>-bolt-instrumented <args>"
        echo "Then create final binary:"
        echo "  cargo pgo bolt optimize --with-pgo"
      fi

      profileoff
      echo "✅ PGO optimization complete"
    fi
    ;;
esac

echo ""
echo "✅ All operations complete"
