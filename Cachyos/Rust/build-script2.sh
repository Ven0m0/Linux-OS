#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# --- Configurable Defaults ---
PGO=0      # 0=build, 1=instrument, 2=optimize
BOLT=0
GIT=0
ARGS=()
JOBS=$(nproc)

# --- Parse Arguments ---
while (($#)); do
  case "$1" in
    --pgo)   shift; [[ "$1" =~ ^[0-2]$ ]] || { echo "Error: --pgo must be 0|1|2"; exit 1; }; PGO="$1"; shift ;;
    --bolt)  BOLT=1; shift ;;
    --git)   GIT=1; shift ;;
    --)      shift; ARGS+=("$@"); break ;;
    *)       ARGS+=("$1"); shift ;;
  esac
done

# --- Save Current System Settings ---
read_sysfs() { [[ -r "$1" ]] && cat "$1" || echo ""; }
ORIG_KPTR=$(read_sysfs /proc/sys/kernel/kptr_restrict)
ORIG_PERF=$(read_sysfs /proc/sys/kernel/perf_event_paranoid)
ORIG_TURBO=$(read_sysfs /sys/devices/system/cpu/intel_pstate/no_turbo)
ORIG_HUGE=$(read_sysfs /sys/kernel/mm/transparent_hugepage/enabled)

cleanup() {
  set +e
  echo "$ORIG_KPTR"  | sudo tee /proc/sys/kernel/kptr_restrict >/dev/null
  echo "$ORIG_PERF"  | sudo tee /proc/sys/kernel/perf_event_paranoid >/dev/null
  echo "$ORIG_TURBO" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null
  echo "$ORIG_HUGE"  | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null
  cargo-cache -efg
  cargo clean
  rm -rf "$HOME/.cache/sccache/"*
}
trap cleanup ERR EXIT

# --- Performance Tuning ---
sudo -v
sudo cpupower frequency-set --governor performance
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null

# --- Optional Rust Update ---
read -rp "Update Rust toolchain? [y/N] " REPLY
[[ "$REPLY" =~ ^[Yy]$ ]] && rustup update >/dev/null 2>&1 || :

# --- Ensure Required Tools ---
for tool in cargo-pgo cargo-shear cargo-machete cargo-cache; do
  command -v "$tool" >/dev/null || cargo install "$tool"
done

# --- Optional Git Cleanup ---
if (( GIT )); then
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive
  git repack -ad --depth=250 --window=250
  git clean -fdX
fi

# --- Compiler Setup (prefer sccache + clang) ---
if command -v sccache >/dev/null; then
  export CC="sccache clang" CXX="sccache clang++" RUSTC_WRAPPER=sccache
  SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server >/dev/null || :
else
  export CC=clang CXX=clang++
fi
export CPP=clang-cpp AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib STRIP=llvm-strip

# --- Cargo Environment ---
unset CARGO_ENCODED_RUSTFLAGS
export CARGO_PROFILE_RELEASE_LTO=true
export CARGO_BUILD_JOBS="$JOBS"
export CARGO_INCREMENTAL=0
export RUSTC_BOOTSTRAP=1
export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
export MALLOC_CONF="thp:always,metadata_thp:always,tcache:true,percpu_arena:percpu"
export _RJEM_MALLOC_CONF="$MALLOC_CONF"
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C lto=on -Z tune-cpu=native"

# --- Pre-build Maintenance ---
cargo update --recursive
cargo fix --workspace --all-targets --allow-dirty -r
cargo clippy --fix --workspace --allow-dirty
cargo fmt
cargo +nightly udeps
cargo-shear --fix
cargo-machete --fix
cargo-cache -g -f -e clean-unref

# --- Profiling Helpers ---
profile_on() {
  sudo sysctl -w kernel.randomize_va_space=0
  sudo sysctl -w kernel.nmi_watchdog=0
  echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null
  sudo cpupower frequency-set --governor performance
}
profile_off() {
  sudo sysctl -w kernel.randomize_va_space=1
  echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null
}

profile_on

# --- PGO Phases ---
case "$PGO" in
  0) cargo pgo build --release "${ARGS[@]}" ;;
  1) cargo pgo instr build --release "${ARGS[@]}"; exit ;;
  2) cargo pgo opt build --release "${ARGS[@]}" ;;
esac

# --- BOLT Optimization ---
if (( BOLT )); then
  cargo pgo bolt build --with-pgo --release "${ARGS[@]}"
  cargo pgo bolt optimize --with-pgo --release "${ARGS[@]}"
fi

# --- Final Build ---
cargo +nightly build --release "${ARGS[@]}"

profile_off
