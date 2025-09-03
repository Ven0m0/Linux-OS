#!/usr/bin/env bash
set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar inherit_errexit
export LC_ALL=C LANG=C
# —————— Tweaks ——————
if [[ $EUID -ne 0 ]]; then
  echo "This script requires root privileges. Validating with sudo..."
  sudo -v || { echo "Sudo failed. Exiting."; exit 1; }
fi
sudo cpupower frequency-set --governor performance
MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
export MALLOC_CONF _RJEM_MALLOC_CONF="$MALLOC_CONF"
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null || :
# —————— Update Rust toolchains ——————
read -r -p "Update Rust toolchains? [y/N] " ans
[[ $ans =~ ^[Yy]$ ]] && rustup update >/dev/null 2>&1 || :
# —————— Trap ——————
cleanup() {
  trap - ERR
  set +e
  cargo-cache -efg >/dev/null 2>&1 || :
  cargo clean >/dev/null 2>&1 || :
  rm -rf "$HOME/.cache/sccache/"* >/dev/null 2>&1 || :
  set -e
}
trap cleanup ERR
# —————— Defaults & help ——————
USE_MOLD=0; LOCKED_FLAG=""; CRATES=()

usage() {
  cat <<EOF >&2
Usage: $0 [-m|-mold] [-l|--locked] <crate> [-h|--help]

Options:
  -m|-mold       use mold as the linker
  -l|--locked    pass --locked to cargo install
  -h|--help      show this help and exit
  <crate>        one or more crates to install

Examples:
  $0 ripgrep
  $0 -m --locked bat fd
EOF
  exit "${1:-1}"
}

# —————— Parse args ——————
if [ "$#" -eq 0 ]; then
  echo "Error: at least one <crate> is required" >&2
  usage 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -m|--mold) USE_MOLD=1; shift ;;
    -l|--locked) LOCKED_FLAG="--locked"; shift ;;
    -h|--help) usage 0 ;;
    --) shift; break ;;
    -*) echo >&2 "Error: unknown option '$1'"; usage 1 ;;
    *) CRATES+=("$1"); shift ;;
  esac
done
# —————— Prepare environment ——————
jobs="$(nproc)"
cd "$HOME"
# ensure RUSTFLAGS is set
: "${RUSTFLAGS:=}"

# https://github.com/rust-lang/rust/blob/master/src/ci/run.sh
# Use sccache if installed
if command -v sccache >/dev/null 2>&1; then
  export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache
  SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server 2>/dev/null || :
else
  export CC="clang" CXX="clang++"
  unset RUSTC_WRAPPER
fi
export CPP="clang-cpp"
export AR="llvm-ar" NM="llvm-nm" RANLIB="llvm-ranlib"
export STRIP="llvm-strip"
# Make sure rustflags arent being overwritten by cargo
unset CARGO_ENCODED_RUSTFLAGS
# Cargo settings/tweaks
export CARGO_CACHE_RUSTC_INFO=1 
export CARGO_HTTP_SSL_VERSION="tlsv1.3" CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
export CARGO_INCREMENTAL=0
export RUSTC_BOOTSTRAP=1
export CARGO_PROFILE_RELEASE_LTO=true
export CARGO_BUILD_JOBS="$jobs"
export CARGO_FUTURE_INCOMPAT_REPORT_FREQUENCY=never CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
# export RUSTUP_TOOLCHAIN=nightly
LFLAGS=(-Clinker=clang -Clink-arg=-fuse-ld=lld -Clinker-features=lld)
CLDFLAGS=(-fuse-ld=lld)

# —————— Core optimization flags ——————
CFLAGS="-march=native -mtune=native -O3 -pipe -pthread -fdata-sections -ffunction-sections"
CXXFLAGS="$CFLAGS"
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

# https://github.com/johnthagen/min-sized-rust / https://doc.rust-lang.org/rustc/codegen-options/index.html
# https://nnethercote.github.io/perf-book/build-configuration.html
# "-Clink-arg=-flto" needed for mold
# -Cembed-bitcode=y / might not needed with "-Clinker-plugin-lto"

RUSTFLAGS_BASE=(
  -Copt-level=3
  -Ctarget-cpu=native
  -Ccodegen-units=1
  -Cstrip=symbols
  -Clto=fat
  -Clink-arg=-flto
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
EXTRA_LINK=(
  -Clink-arg=-Wl,-O3
  -Clink-arg=-Wl,-gc-sections
  -Clink-arg=-Wl,--icf=all
  -Clink-arg=-Wl,--sort-common
  -Clink-arg=-Wl,--as-needed
  -Clink-arg=-Wl,-z,now
  #-Clink-arg=--lto-emit-llvm
  -Clink-arg=-Wl,--lto-O3
)
ZFLAGS=(-Zunstable-options -Zfewer-names -Zcombine-cgu -Zmerge-functions=aliases -Zno-embed-metadata -Zmir-opt-level=3 -Zchecksum-hash-algorithm=blake3 -Zprecise-enum-drop-elaboration=yes)
# -Z min-function-alignment=64
# -Z precise-enum-drop-elaboration=yes # Codegen lto/pgo
# RUSTFLAGS="-C llvm-args=-polly -C llvm-args=-polly-vectorizer=polly"
# -Z llvm-plugins=LLVMPolly.so -C llvm-args=-polly-vectorizer=stripmine
# -Z llvm-plugins=/usr/lib/LLVMPolly.so

# Combine all rustflags into one exported variable
export RUSTFLAGS="${RUSTFLAGS_BASE[@]} ${LFLAGS[@]} ${ZFLAGS[@]} ${EXTRA_LINK[@]}"
export CFLAGS="${CFLAGS[@]}"
export CXXFLAGS="${CXXFLAGS[@]}"
export LDFLAGS="${LDFLAGS[@]}"

# Additional flags for cargo install
INSTALL_FLAGS=(-Zunstable-options -Zgit -Zgitoxide -Zno-embed-metadata)
MISC_OPT=(--ignore-rust-version -f --bins -j"$jobs")

# —————— Install the crates ——————
sync
echo "Installing ${CRATES[@]} with Mold=${USE_MOLD} and ${LOCKED_FLAG}..."
for crate in "${CRATES[@]}"; do
  printf '→ Installing "%s"…\n' "$crate"
  cargo +nightly "${INSTALL_FLAGS[@]}" install "$LOCKED_FLAG" "${MISC_OPT[@]}" "$crate"
  printf '🎉 %s installed in %s/.cargo/bin\n' "$crate" "$HOME"
done
exit 0
