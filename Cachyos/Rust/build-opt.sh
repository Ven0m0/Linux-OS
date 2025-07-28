#!/usr/bin/env bash
set -eEChuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar inherit_errexit
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
# —————— Trap ——————
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
# —————— Speed and caching ——————
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
sudo -v
hash -r; hash cargo rustc clang nproc sccache
sudo cpupower frequency-set --governor performance
export MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
export _RJEM_MALLOC_CONF="$MALLOC_CONF"
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null || :
# —————— Update Rust toolchains ——————
read -r -p "Update Rust toolchains? [y/N] " ans
[[ $ans =~ ^[Yy]$ ]] && rustup update >/dev/null 2>&1 || :
# —————— Defaults & help ——————
PGO=0; BOLT=0; GIT=0; ARGS=()
debug () {
  export RUST_LOG=trace RUST_BACKTRACE=1; set -x
}

usage() {
  cat <<EOF >&2
Usage: $0 [-m|-mold] [-l|--locked] <crate> [-h|--help]

Options:
  -p|-pgo       use PGO to optimize the crate
  -b|-bolt      use BOLT and PGO to optimize
  -g|-git       Clean the crate up through git first
  -d|-debug     Verbose output for debug
  -h|--help     show this help and exit
  <crate>       one or more crates to install

Examples:
  $0 -pgo
  $0 -bolt
  $0 -pgo -git -debug
EOF
  exit "${1:-1}"
}

# parse
while (($#)); do
  case $1 in
    -p|-pgo) PGO=1; shift ;;
    -b|-bolt) BOLT=1; shift ;;
    -g|-git) GIT=1; shift ;;
    -d|-debug) debug; shift ;;
    -h|--help) usage 0 ;;
    --) shift; ARGS=("$@"); break ;;
    *) ARGS+=("$1"); shift;;
  esac
done
# —————— Prepare environment ——————
jobs=$(nproc)
cd "$HOME"
# ensure RUSTFLAGS is set
: "${RUSTFLAGS:=}"
export CARGO_HTTP_SSL_VERSION="tlsv1.3" CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
export CARGO_CACHE_RUSTC_INFO=1 
export CARGO_FUTURE_INCOMPAT_REPORT_FREQUENCY=never CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
# —————— Tuning ——————
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
# —————— Ensure Required Tools ——————
for tool in cargo-shear cargo-machete cargo-cache ; do
  command -v "$tool" >/dev/null || cargo install "$tool" || :
done
# —————— Compiler Setup (prefer sccache + clang) ——————
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
# —————— Cargo Environment ——————
unset CARGO_ENCODED_RUSTFLAGS
export RUSTUP_TOOLCHAIN=nightly
export CARGO_BUILD_JOBS="$jobs"
export CARGO_PROFILE_RELEASE_LTO=true
export CARGO_INCREMENTAL=0
export RUSTC_LINKER=clang

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
# —————— Git Cleanup ——————
if (( GIT )); then
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive
  git repack -ad --depth=250 --window=250
  git clean -fdX
fi
Scope="--workspace --allow-dirty --allow-staged --allow-no-vcs"
# —————— Update ——————
cargo update --recursive >/dev/null 2>&1 || :
cargo upgrade --recursive --pinned allow >/dev/null 2>&1 || :
# —————— Minify ——————
cargo +nightly udeps --workspace --release --all-features --keep-going >/dev/null 2>&1 || :
cargo-shear --fix >/dev/null 2>&1 || :
cargo-machete --fix >/dev/null 2>&1 || :
cargo-machete --fix --with-metadata >/dev/null 2>&1 || :
cargo-minify "$Scope" --apply >/dev/null 2>&1 || :
# —————— Lint ——————
cargo fix "$Scope" --all-targets --all-features -r --bins >/dev/null 2>&1 || :
cargo fix "$Scope" --edition-idiom --all-features --bins --lib -r >/dev/null 2>&1 || :
cargo clippy --all-targets >/dev/null 2>&1 || :
cargo clippy --fix "$Scope" --all-features >/dev/null 2>&1 || :
cargo fmt --all >/dev/null 2>&1 || :
cargo-sort -w --order package,dependencies,features >/dev/null 2>&1 || :
cargo-cache -g -f -e clean-unref >/dev/null 2>&1 || :
# —————— General flags ——————
NIGHTLYFLAGS="-Z unstable-options -Z gc -Z git -Z gitoxide -Z checksum-hash-algorithm=blake3 -Z precise-enum-drop-elaboration=yes"
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C lto=on -C embed-bitcode=yes -C relro-level=off -C debuginfo=0 -C strip=symbols -C debuginfo=0 -C force-frame-pointers=no -C link-dead-code=no \
-Z tune-cpu=native -Z default-visibility=hidden  -Z location-detail=none -Z function-sections $NIGHTLYFLAGS -Zcombine-cgu"
CARGO_NIGHTLY="-Zno-embed-metadata"
# Experimental rustc -Zmir-opt-level=3
# Only for compile speed
# RUSTFLAGS="-Zfewer-names"
# -Z min-function-alignment=64
# Polly todo
# RUSTFLAGS="-C llvm-args=-polly -C llvm-args=-polly-vectorizer=polly"
# -Z llvm-plugins=LLVMPolly.so -C llvm-args=-polly-vectorizer=stripmine
# -Z llvm-plugins=/usr/lib/LLVMPolly.so
# —————— Profile accuracy ——————
profileon () {
    sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space" || :
    sudo sh -c "echo 0 > /proc/sys/kernel/nmi_watchdog" || :
    # sudo sysctl -w kernel.randomize_va_space=0
    # sudo sysctl -w kernel.nmi_watchdog=0
    sudo sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo" || :
    # Allow to profile with branch sampling, no perf sudo requirement
    sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict" || :
    sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid" || :
    PGOFLAGS="-Cstrip=debuginfo -Z debug-info-for-profiling"
    RUSTFLAGS="$RUSTFLAGS -Cembed-bitcode=y -Zprecise-enum-drop-elaboration=yes $PGOFLAGS"
}
profileoff () {
    sudo sh -c "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo" || :
    PGOFLAGS="-C strip=symbols -Cembed-bitcode=y -Zprecise-enum-drop-elaboration=yes"
}
# -Cprofile-use
PGO2="-Cllvm-args=-pgo-warn-missing-function -C profile-correction"
# whole crate + std LTO & PGO
if (( FULL )); then
  FULLPGO="-Z build-std=std,panic_abort -Z build-std-features=panic_immediate_abort"
  export RUSTC_BOOTSTRAP=1
fi
# —————— PGO Phases ——————
if (( PGO )); then
  cargo pgo clean
  profileon >/dev/null 2>&1 || :
  # Build PGO instrumented binary
  cargo pgo build
  # Run binary to gather profiles
  cargo pgo test
  cargo pgo bench
  hyperfine "/target/x86_64-unknown-linux-gnu/release/<binary>"
  #perf record -e cycles:u --call-graph dwarf -o pgo.data -- ./target/.../binary
  #perf record -e cycles:u -j any,u --call-graph dwarf -o pgo.data -- ./target/.../binary
  export RUSTFLAGS="-Cembed-bitcode=y -Zprofile-sample-use -Cprofile-use $PGO2"
  cargo pgo optimize
fi
# —————— BOLT Phases ——————
if (( BOLT )); then
  cargo pgo clean
  profileon >/dev/null 2>&1 || :
  export RUSTFLAGS="$RUSTFLAGS -Clink-args=-Wl,--emit-relocs"
  # Build PGO instrumented binary
  cargo pgo build
  # Run binary to gather profiles
  cargo pgo test
  cargo pgo bench
  hyperfine "/target/x86_64-unknown-linux-gnu/release/"
  #perf record -e cycles:u --call-graph dwarf -o pgo.data -- ./target/.../binary
  #perf record -e cycles:u -j any,u --call-graph dwarf -o pgo.data -- ./target/.../binary
  # Build BOLT instrumented binary using PGO profiles
  export RUSTFLAGS="-Cembed-bitcode=y -Z profile-sample-use $PGO2"
  cargo pgo bolt build --with-pgo
  # Run binary to gather BOLT profiles
  hyperfine "/target/x86_64-unknown-linux-gnu/release/<binary>-bolt-instrumented"
  # Optimize a PGO-optimized binary with BOLT
  export RUSTFLAGS="-Cembed-bitcode=y -Z profile-sample-use"
  cargo pgo bolt optimize --with-pgo
fi
profileoff >/dev/null 2>&1 || :
# —————— Todo ——————
# LastBuild="-C strip=symbols -Z trim-paths"
export CARGO_TRIM_PATHS=all
# cargo +nightly ${NIGHTLYFLAGS} build --release -Zbuild-std=std,panic_abort -Zbuild-std-features=panic_immediate_abort
