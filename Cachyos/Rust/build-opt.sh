#!/usr/bin/env bash
shopt -s nullglob globstar inherit_errexit
export LC_ALL=C LANG=C
sudo -v
cleanup() {
  trap - ERR EXIT HUP QUIT TERM INT ABRT
  set +e
  cargo-cache -efg &>/dev/null
  cargo clean &>/dev/null
  cargo pgo clean &>/dev/null
  rm -f "${HOME}/.cache/sccache/"* &>/dev/null
  set -e
}
trap cleanup ERR EXIT HUP QUIT TERM INT ABRT
read -r -p "Update Rust toolchains? [y/N] " ans
[[ $ans =~ ^[Yy]$ ]] && sudo rustup update &>/dev/null
sudo cpupower frequency-set --governor performance &>/dev/null
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled &>/dev/null
MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
export MALLOC_CONF _RJEM_MALLOC_CONF="$MALLOC_CONF"
read -r -p "Update Rust toolchains? [y/N] " ans
[[ $ans =~ ^[Yy]$ ]] && rustup update &>/dev/null
PGO=0
BOLT=0
GIT=0
ARGS=()
debug() {
  export RUST_LOG=trace RUST_BACKTRACE=1
  set -x
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

if [[ $# -eq 0 ]]; then
  echo "Error: at least one <crate> is required" >&2
  usage 1
fi

while (($#)); do
  case $1 in
  -p | -pgo)
    PGO=1
    shift
    ;;
  -b | -bolt)
    BOLT=1
    shift
    ;;
  -g | -git)
    GIT=1
    shift
    ;;
  -d | -debug)
    debug
    shift
    ;;
  -h | --help) usage 0 ;;
  --)
    shift
    ARGS=("$@")
    break
    ;;
  -*)
    echo >&2 "Error: unknown option '$1'"
    usage 1
    ;;
  *)
    ARGS+=("$1")
    shift
    ;;
  esac
done
command -v cargo-pgo &>/dev/null || { rustup component add llvm-tools-preview && cargo install cargo-pgo; }
# target.x86_64-unknown-linux-gnu.rustflags might be nessecary for cargo-pgo
tool="cargo-shear cargo-machete cargo-cache"
for tool in cargo-shear cargo-machete cargo-cache; do
  command -v "$tool" &>/dev/null || cargo install "$tool"
done
# https://github.com/rust-lang/rust/blob/master/src/ci/run.sh
if command -v sccache &>/dev/null; then
  export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache SCCACHE_DIRECT=true SCCACHE_RECACHE=true SCCACHE_IDLE_TIMEOUT=10800
  sccache --start-server
else
  export CC="clang" CXX="clang++"
  unset RUSTC_WRAPPER SCCACHE_DIRECT SCCACHE_RECACHE SCCACHE_IDLE_TIMEOUT
fi
#export CPP=clang-cpp AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib STRIP=llvm-strip
jobs=$(nproc 2>/dev/null)
: "${RUSTFLAGS:=}" # ensure RUSTFLAGS is set
export CARGO_CACHE_RUSTC_INFO=1 CARGO_FUTURE_INCOMPAT_REPORT_FREQUENCY=never CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_HTTP_SSL_VERSION="tlsv1.3"
export RUSTC_BOOTSTRAP=1 RUSTUP_TOOLCHAIN=nightly
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER
export CARGO_BUILD_JOBS="$jobs"
export CARGO_PROFILE_RELEASE_LTO=true CARGO_INCREMENTAL=0
export RUSTC_LINKER=clang
#LFLAGS=(-Clinker=clang -Clink-arg=-fuse-ld=lld -Clinker-features=lld)
#CLDFLAGS=(-fuse-ld=lld)
if ((GIT)) && git rev-parse --is-inside-work-tree &>/dev/null; then
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive
  git repack -ad --depth=250 --window=250
  git clean -fdX
fi
Scope="--workspace --allow-dirty --allow-staged --allow-no-vcs"
cargo update --recursive &>/dev/null
cargo upgrade --recursive --pinned allow &>/dev/null
cargo +nightly udeps --workspace --release --all-features --keep-going &>/dev/null
cargo-shear --fix &>/dev/null
cargo-machete --fix &>/dev/null
cargo-machete --fix --with-metadata &>/dev/null
cargo-minify "$Scope" --apply &>/dev/null
cargo fix "$Scope" --all-targets --all-features -r --bins &>/dev/null
cargo fix "$Scope" --edition-idiom --all-features --bins --lib -r &>/dev/null
cargo clippy --all-targets &>/dev/null
cargo clippy --fix "$Scope" --all-features &>/dev/null
cargo fmt --all &>/dev/null
cargo-sort -w --order package,dependencies,features &>/dev/null
cargo-cache -g -f -e clean-unref &>/dev/null
NIGHTLYFLAGS="-Z unstable-options -Ztune-cpu=native -Zdefault-visibility=hidden -Z precise-enum-drop-elaboration=y -Zlocation-detail=none -Zfunction-sections -Zcombine-cgu"
RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Clto=fat -Cembed-bitcode=y -Crelro-level=off -Cdebuginfo=0 -Cforce-frame-pointers=no -Clink-dead-code=no $NIGHTLYFLAGS"
CARGO_NIGHTLY="-Z gc -Z git -Z gitoxide -Zno-embed-metadata -Zfewer-names"
# Only for compile speed
# -Z min-function-alignment=64
# Polly todo
# RUSTFLAGS="-C llvm-args=-polly -C llvm-args=-polly-vectorizer=polly"
# -Z llvm-plugins=LLVMPolly.so -C llvm-args=-polly-vectorizer=stripmine
# -Z llvm-plugins=/usr/lib/LLVMPolly.so
profileon() {
  sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space"
  sudo sh -c "echo 0 > /proc/sys/kernel/nmi_watchdog"
  sudo sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo"
  # Allow to profile with branch sampling, no perf sudo requirement
  sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
  sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid"
  PGOFLAGS="-Cstrip=debuginfo -Zdebug-info-for-profiling"
  RUSTFLAGS="${RUSTFLAGS} ${PGOFLAGS}"
}
profileoff() {
  sudo sh -c "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo"
  PGOFLAGS="-Cstrip=symbols"
}
# -Cprofile-use
PGO2="-Cllvm-args=-pgo-warn-missing-function -Cprofile-correction"
# whole crate + std LTO & PGO
if ((FULL)); then
  FULLPGO="-Z build-std=std,panic_abort -Z build-std-features=panic_immediate_abort"
fi
if ((PGO)); then
  cargo clean
  cargo pgo clean
  profileon
  # Build PGO instrumented binary
  cargo pgo build
  # Run binary to gather profiles
  cargo test
  cargo pgo test
  cargo pgo bench
  hyperfine "/target/x86_64-unknown-linux-gnu/release/<binary>"
  #perf record -e cycles:u --call-graph dwarf -o pgo.data -- ./target/x86_64-unknown-linux-gnu/release/binary
  #perf record -e cycles:u -j any,u --call-graph dwarf -o pgo.data -- ./target/x86_64-unknown-linux-gnu/release/binary
  export RUSTFLAGS="-Cembed-bitcode=y -Zprofile-sample-use -Cprofile-use $PGO2"
  cargo pgo optimize
fi
if ((BOLT)); then
  cargo clean
  cargo pgo clean
  profileon
  export RUSTFLAGS="${RUSTFLAGS} -Clink-args=-Wl,--emit-relocs"
  # Build PGO instrumented binary
  cargo pgo build
  # Run binary to gather profiles
  cargo test
  cargo pgo test
  cargo pgo bench
  hyperfine "/target/x86_64-unknown-linux-gnu/release/"
  #perf record -e cycles:u --call-graph dwarf -o pgo.data -- ./target/.../binary
  #perf record -e cycles:u -j any,u --call-graph dwarf -o pgo.data -- ./target/.../binary
  # Build BOLT instrumented binary using PGO profiles
  RUSTFLAGS+="-Cembed-bitcode=y -Zprofile-sample-use ${PGO2}"
  cargo pgo bolt build --with-pgo
  # Run binary to gather BOLT profiles
  hyperfine "/target/x86_64-unknown-linux-gnu/release/<binary>-bolt-instrumented"
  # Optimize a PGO-optimized binary with BOLT
  export RUSTFLAGS="-Cembed-bitcode=y -Z profile-sample-use"
  cargo pgo bolt optimize --with-pgo
fi
profileoff
# LastBuild="-C strip=symbols -Z trim-paths"
export CARGO_TRIM_PATHS=all
# cargo +nightly ${NIGHTLYFLAGS} build --release -j"$jobs" -Zbuild-std=std,panic_abort -Zbuild-std-features=panic_immediate_abort
