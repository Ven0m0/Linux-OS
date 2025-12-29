#!/usr/bin/env bash
# rustbuild.sh - Optimized Rust Build & PGO/BOLT Orchestrator
set -euo pipefail; shopt -s nullglob globstar; IFS=$'\n\t'
export LC_ALL=C LANG=C

# --- Config & Helpers ---
: "${MODE:=build}" "${PGO:=0}" "${BOLT:=0}" "${CLEAN:=0}" "${MOLD:=0}" "${DRY:=0}"
: "${RUSTFLAGS:=${RUSTFLAGS:-}}" "${CARGO_TARGET_DIR:=target}"
ARGS=() CRATES=()

R=$'\e[31m' G=$'\e[32m' B=$'\e[34m' X=$'\e[0m'
log() { printf "%b[+]%b %s\n" "$B" "$X" "$*"; }
die() { printf "%b[!]%b %s\n" "$R" "$X" "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null; }
run() { ((DRY)) && log "[DRY] $*" || "$@"; }

cleanup() {
  set +e
  [[ -n ${SCCACHE_DIR:-} ]] && rm -rf "$SCCACHE_DIR"/* 2>/dev/null
  has cargo-cache && cargo-cache -efg >/dev/null 2>&1
}
trap cleanup EXIT

# --- Core Logic ---
check_deps() {
  has cargo || die "Cargo not found"
  if ((PGO || BOLT)); then
    has cargo-pgo || die "cargo-pgo required (cargo install cargo-pgo)"
    [[ $MODE == "build" ]] && die "PGO/BOLT requires explicit mode (e.g. --release)"
  fi
  ((MOLD)) && ! has mold && die "Mold linker not found"
}

setup_flags() {
  # Common optimization flags
  ((MOLD)) && RUSTFLAGS+=" -C link-arg=-fuse-ld=mold"
  export RUSTFLAGS
}

build_pgo() {
  local stage=$1
  log "PGO Stage: $stage"
  
  if [[ $stage == "instrument" ]]; then
    # Stage 1: Instrumentation
    run cargo pgo build "${ARGS[@]}"
    log "Instrumentation done. Run your workload now, then run with --pgo 2"
  elif [[ $stage == "optimize" ]]; then
    # Stage 2: Optimization
    [[ -d "pgo-data" ]] || die "No PGO data found. Run stage 1 first."
    
    # Merge profiles (handled by cargo-pgo, but explicit check is good)
    log "Optimizing with PGO data..."
    run cargo pgo build --merge "${ARGS[@]}"
    
    if ((BOLT)); then
      log "Applying BOLT optimization..."
      has llvm-bolt || die "llvm-bolt missing"
      run cargo pgo bolt build "${ARGS[@]}"
    fi
  fi
}

build_normal() {
  log "Building ${CRATES[*]:-project}..."
  run cargo build "${ARGS[@]}" "${CRATES[@]}"
}

usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS] [CRATES...]
Options:
  -r, --release    Build in release mode
  --pgo N          PGO Mode: 1=Instrument, 2=Optimize
  --bolt           Enable BOLT (requires PGO=2)
  --mold           Use Mold linker
  --clean          Clean before build
  --dry            Dry run
EOF
  exit 0
}

# --- Main ---
while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--release) ARGS+=("--release") ;;
    --pgo) PGO="$2"; shift ;;
    --bolt) BOLT=1 ;;
    --mold) MOLD=1 ;;
    --clean) CLEAN=1 ;;
    --dry) DRY=1 ;;
    -h|--help) usage ;;
    -*) ARGS+=("$1") ;;
    *) CRATES+=("$1") ;;
  esac; shift
done

main() {
  check_deps
  setup_flags
  
  ((CLEAN)) && { log "Cleaning..."; run cargo clean; }
  
  if ((PGO == 1)); then
    build_pgo "instrument"
  elif ((PGO == 2)); then
    build_pgo "optimize"
  else
    build_normal
  fi
  
  log "Done."
}

main
