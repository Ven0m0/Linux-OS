#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar

# —————————————————————————————————————————————————————
# Speed and caching
LC_ALL=C LANG=C.UTF-8
hash -r
hash cargo rustc clang git nproc sccache cat sudo
sudo cpupower frequency-set --governor performance

# —————————————————————————————————————————————————————
# defaults
PGO=0; BOLT=0; GIT=0; ARGS=()

# parse
while (($#)); do
  case $1 in
    --pgo)   shift; [[ $1 =~ ^[0-2]$ ]]||{ echo "--pgo needs 0|1|2";exit 1;} ; PGO=$1;shift;;
    --bolt)  BOLT=1; shift;;
    --git)   GIT=1; shift;;
    --)      shift; ARGS=("$@"); break;;
    *)       ARGS+=("$1"); shift;;
  esac
done

# save orig
o1=$(< /proc/sys/kernel/kptr_restrict)
o2=$(< /proc/sys/kernel/perf_event_paranoid)
o3=$(< /sys/devices/system/cpu/intel_pstate/no_turbo)
o4=$(< /sys/kernel/mm/transparent_hugepage/enabled)

trap 'trap - ERR EXIT; set +e
  cargo-cache -efg; cargo clean; rm -rf "$HOME/.cache/sccache/"*
  echo $o1|sudo tee /proc/sys/kernel/kptr_restrict>/dev/null
  echo $o2|sudo tee /proc/sys/kernel/perf_event_paranoid>/dev/null
  echo $o3|sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo>/dev/null
  echo $o4|sudo tee /sys/kernel/mm/transparent_hugepage/enabled>/dev/null' ERR EXIT

sudo cpupower frequency-set --governor performance
sudo -v
read -rp"Update Rust? [y/N] " A
[[ $A =~ [Yy] ]]&&rustup update>/dev/null 2>&1||:

for t in cargo-pgo cargo-shear cargo-machete cargo-cache;do command -v "$t"||cargo install "$t";done

(( GIT ))&&{
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive
  git repack -ad --depth=250 --window=250
  git clean -fdX
}

jobs=$(nproc)
if command -v sccache>/dev/null;then
  export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache
  SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server>/dev/null||:
else
  export CC=clang CXX=clang++
fi
export CPP=clang-cpp AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib STRIP=llvm-strip
unset CARGO_ENCODED_RUSTFLAGS
export CARGO_PROFILE_RELEASE_LTO=true CARGO_BUILD_JOBS=$jobs CARGO_INCREMENTAL=0 RUSTC_BOOTSTRAP=1
export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
export MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
export _RJEM_MALLOC_CONF="$MALLOC_CONF"
echo always|sudo tee /sys/kernel/mm/transparent_hugepage/enabled>/dev/null

cargo update --recursive
cargo fix --workspace --all-targets --allow-dirty -r
cargo clippy --fix --workspace --allow-dirty
cargo fmt
cargo +nightly udeps
cargo-shear --fix
cargo-machete --fix
cargo-cache -g -f -e clean-unref

export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C lto=on -Z tune-cpu=native"
profileon(){sudo sysctl -w kernel.randomize_va_space=0;sudo sysctl -w kernel.nmi_watchdog=0;echo 1|sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo>/dev/null;sudo cpupower frequency-set --governor performance;}
profileoff(){sudo sysctl -w kernel.randomize_va_space=1;echo 0|sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo>/dev/null;}
profileon

case $PGO in
  0) cargo pgo build --release "${ARGS[@]}" ;;
  1) cargo pgo instr build --release "${ARGS[@]}"; exit ;;
  2) cargo pgo opt build --release "${ARGS[@]}" ;;
  *) echo "Invalid --pgo"; exit 1 ;;
esac

(( BOLT ))&&{
  cargo pgo bolt build   --with-pgo --release "${ARGS[@]}"
  cargo pgo bolt optimize --with-pgo --release "${ARGS[@]}"
}

cargo +nightly build --release "${ARGS[@]}"
profileoff
