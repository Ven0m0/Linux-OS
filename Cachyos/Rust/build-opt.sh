#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_ALL=C LANG=C.UTF-8; set -CE
hash -r; hash cargo rustc clang git nproc sccache cat sudo
# —————————————————————————————————————————————————————
# Clean up cargo cache on error
cleanup() {
  trap - ERR EXIT HUP QUIT TERM INT ABRT
  set +e
  cargo-cache -efg >/dev/null 2>&1 || :
  cargo clean >/dev/null 2>&1 || :
  cargo pgo clean >/dev/null 2>&1 || :
  rm -rf "$HOME/.cache/sccache/"* >/dev/null 2>&1 || :
  set -e
}
trap cleanup ERR EXIT HUP QUIT TERM INT ABRT
# —————————————————————————————————————————————————————
# Defaults
PGO=0; BOLT=0; GIT=0; ARGS=()

debug () {
  export RUST_LOG=trace
  export RUST_BACKTRACE=1
  set -x
}

# parse
while (($#)); do
  case $1 in
    -p|-pgo)   PGO=1; shift;;
    -b|-bolt)  BOLT=1; shift;;
    -g|-git)   GIT=1; shift;;
    -d|-debug) debug; shift;;
    --)      shift; ARGS=("$@"); break;;
    *)       ARGS+=("$1"); shift;;
  esac
done
# —————————————————————————————————————————————————————
# Prepare environment
jobs=$(nproc)
cd "$HOME"
# ensure RUSTFLAGS is set
: "${RUSTFLAGS:=}"
export CARGO_HTTP_SSL_VERSION="tlsv1.3" CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
export CARGO_CACHE_RUSTC_INFO=1 
export CARGO_FUTURE_INCOMPAT_REPORT_FREQUENCY=never CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
# —————————————————————————————————————————————————————
# ---Tuning ---
sudo -v
sudo cpupower frequency-set --governor performance || :
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null || :
export MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
export _RJEM_MALLOC_CONF="$MALLOC_CONF"

if command -v cargo-pgo >/dev/null 2>&1; then
  cargo install cargo-pgo
  rustup component add llvm-tools-preview
fi
# target.x86_64-unknown-linux-gnu.rustflags might be nessecary for cargo-pgo

# --- Ensure Required Tools ---
for tool in cargo-shear cargo-machete cargo-cache ; do
  command -v "$tool" >/dev/null || cargo install "$tool" || :
done

# --- Compiler Setup (prefer sccache + clang) ---
# https://github.com/rust-lang/rust/blob/master/src/ci/run.sh
if command -v sccache >/dev/null 2>&1; then
  export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache
  SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server 2>/dev/null || :
else
  export CC="clang" CXX="clang++"
  unset RUSTC_WRAPPER
fi
# Otherwise double sccache
unset RUSTC_WORKSPACE_WRAPPER

export CPP=clang-cpp AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib STRIP=llvm-strip
# --- Cargo Environment ---
unset CARGO_ENCODED_RUSTFLAGS
export RUSTUP_TOOLCHAIN=nightly
export CARGO_BUILD_JOBS="$jobs"
export CARGO_PROFILE_RELEASE_LTO=true
export CARGO_INCREMENTAL=0

if ((USE_MOLD)); then
  if command -v mold >/dev/null 2>&1; then
    echo "→ using ld.mold via clang"
    LFLAGS=(-Clinker=clang -Clink-arg=-fuse-ld=mold)
    CLDFLAGS=(-fuse-ld=mold)
  elif command -v clang >/dev/null 2>&1; then
    echo "→ using ld.lld via clang"
    LFLAGS=(-Clinker=clang -Clink-arg=-fuse-ld=lld -Clinker-features=lld)
    CLDFLAGS=(-fuse-ld=lld)
  else
    echo "→ falling back to ld.lld via linker-flavor"
    LFLAGS=(-Clinker-flavor=ld.lld -C linker-features=lld)
    CLDFLAGS=(-fuse-ld=lld)
    # export CARGO_TARGET_x86_64-unknown-linux-gnu_LINKER=lld
  fi
fi

# —————————————————————————————————————————————————————
# --- Optional Git Cleanup ---
if (( GIT )); then
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive
  git repack -ad --depth=250 --window=250
  git clean -fdX
fi

# Update and fix code
cargo update --recursive
cargo upgrade --recursive true
cargo fix --workspace --all-targets --all-features -r --bins --allow-dirty
cargo clippy --fix --workspace --all-targets --all-features --allow-dirty --allow-staged
cargo fmt --all

# Clean and debloat
cargo +nightly udeps
cargo-shear --fix
cargo-machete --fix --with-metadata
cargo-cache -g -f -e clean-unref

# General flags
NIGHTLYFLAGS="-Z unstable-options -Z gc -Z git -Z gitoxide -Z checksum-hash-algorithm=blake3 -Z precise-enum-drop-elaboration=yes"
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C lto=on -C embed-bitcode=yes -C relro-level=off -C debuginfo=0 -C strip=symbols -C debuginfo=0 -C force-frame-pointers=no -C link-dead-code=no \
-Z tune-cpu=native -Z default-visibility=hidden  -Z location-detail=none -Z function-sections $NIGHTLYFLAGS -Zcombine-cgu"
CARGO_NIGHTLY="-Zno-embed-metadata"

# Experimental rustc -Zmir-opt-level=3
# Only for compile speed
# RUSTFLAGS="-Zfewer-names"

# export RUSTC_BOOTSTRAP=1
# whole crate + std LTO & PGO
# export CARGO_FLAGS="-Z build-std=std,panic_abort -Z build-std-features=panic_immediate_abort"
# export RUSTFLAGS="$RUSTFLAGS $CARGOFLAGS"
### Rustflags for pgo:
### export RUSTFLAGS="-Z debug-info-for-profiling -C link-args=-Wl,--emit-relocs"
#PGO 2nd compilation:
#-Cllvm-args=-pgo-warn-missing-function -Cprofile-use -C profile-correction
#perf record -e cycles:u --call-graph dwarf -o pgo.data -- ./target/.../binary
#perf record -e cycles:u -j any,u --call-graph dwarf -o pgo.data -- ./target/.../binary

# RUSTFLAGS+="-Cembed-bitcode=y"
# -Z precise-enum-drop-elaboration=yes # Codegen lto/pgo
# -Z min-function-alignment=64
# Polly todo
# RUSTFLAGS="-C llvm-args=-polly -C llvm-args=-polly-vectorizer=polly"
# -Z llvm-plugins=LLVMPolly.so -C llvm-args=-polly-vectorizer=stripmine
# -Z llvm-plugins=/usr/lib/LLVMPolly.so

# Profile accuracy
profileon () {
    sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space" || :
    sudo sh -c "echo 0 > /proc/sys/kernel/nmi_watchdog" || :
    # sudo sysctl -w kernel.randomize_va_space=0
    # sudo sysctl -w kernel.nmi_watchdog=0
    sudo sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo" || :
    # Allow to profile with branch sampling, no perf sudo requirement
    sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict" || :
    sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid" || :
    PGOFLAGS="-C strip=debuginfo"
}
profileoff () {
    sudo sh -c "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo" || :
}
profileon

# --- PGO Phases ---
if (( PGO )); then
  export RUSTFLAGS="-Cembed-bitcode=y -Zdebug-info-for-profiling"
  cargo pgo clean
  # Build PGO instrumented binary
  cargo pgo build
  # Run binary to gather profiles
  cargo pgo test
  cargo pgo bench
  hyperfine "/target/x86_64-unknown-linux-gnu/release/<binary>"
  export RUSTFLAGS="-Cembed-bitcode=y -Zprofile-sample-use -Cllvm-args=-pgo-warn-missing-function -Cprofile-use -Cprofile-correction"
  cargo pgo optimize
fi
# --- BOLT Phases ---
if (( BOLT )); then
  export RUSTFLAGS="-Cembed-bitcode=y -Zdebug-info-for-profiling -Clink-args=-Wl,--emit-relocs"
  cargo pgo clean
  # Build PGO instrumented binary
  cargo pgo build
  # Run binary to gather profiles
  cargo pgo test
  cargo pgo bench
  hyperfine "/target/x86_64-unknown-linux-gnu/release/"
  # Build BOLT instrumented binary using PGO profiles
  export RUSTFLAGS="-Cembed-bitcode=y -Z profile-sample-use -Cllvm-args=-pgo-warn-missing-function -Cprofile-correction"
  cargo pgo bolt build --with-pgo
  # Run binary to gather BOLT profiles
  hyperfine "/target/x86_64-unknown-linux-gnu/release/<binary>-bolt-instrumented"
  # Optimize a PGO-optimized binary with BOLT
  export RUSTFLAGS="-Cembed-bitcode=y -Z profile-sample-use"
  cargo pgo bolt optimize --with-pgo
fi
profileoff

LastBuild="-C strip=symbols -Z trim-paths"
cargo +nightly ${NIGHTLYFLAGS} build --release
