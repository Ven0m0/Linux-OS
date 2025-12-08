#!/usr/bin/env bash
# Rust project optimization workflow: update deps, lint, minify assets, build
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Colors
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' DEF=$'\e[0m'

# Helpers
has(){ command -v "$1" &>/dev/null; }
log(){ printf '%s\n' "${BLU}→${DEF} $*"; }
warn(){ printf '%s\n' "${YLW}WARN:${DEF} $*"; }
err(){ printf '%s\n' "${RED}ERROR:${DEF} $*" >&2; }
die(){ err "$*"; exit "${2:-1}"; }

# Require cargo
has cargo || die "cargo not found"

# Rust optimization flags
export RUSTFLAGS="-C opt-level=3 -C lto -C codegen-units=1 -C target-cpu=native -C panic=abort"
has clang && RUSTFLAGS+=" -C linker=clang"
has mold && RUSTFLAGS+=" -C link-arg=-fuse-ld=mold"

# Tool detection with fallbacks
FD=$(command -v fd || command -v fdfind || echo "")

# Safe find function using fd or find
find_files(){
  local pattern=$1 path=${2:-.}
  if [[ -n $FD ]]; then
    "$FD" -H -t f "$pattern" "$path" 2>/dev/null || :
  else
    find "$path" -type f -name "$pattern" 2>/dev/null || :
  fi
}

usage(){
  cat <<'EOF'
Usage: rustbuild.sh [OPTIONS]

Rust project optimization workflow:
  1. Update & audit dependencies
  2. Format & lint code
  3. Remove unused deps/dead code
  4. Minify HTML/optimize images
  5. Build optimized release

Options:
  -h, --help     Show this help
  --skip-assets  Skip asset optimization
  --dry-run      Show what would be done

Requirements: cargo, rustc
Optional: cargo-udeps, cargo-shear, cargo-machete, minhtml, oxipng, jpegoptim
EOF
  exit 0
}

# Parse args
SKIP_ASSETS=0 DRY_RUN=0
while (($#)); do
  case "$1" in
    -h|--help) usage;;
    --skip-assets) SKIP_ASSETS=1;;
    --dry-run) DRY_RUN=1;;
    *) warn "Unknown option: $1";;
  esac
  shift
done

run(){ ((DRY_RUN)) && log "[DRY] $*" || "$@"; }

main(){
  log "Starting Rust optimization workflow..."

  # 1. Update & audit deps
  log "Updating dependencies..."
  run cargo update
  has cargo-outdated && run cargo outdated || :

  # 2. Format & lint
  log "Formatting and linting..."
  run cargo fmt
  run cargo clippy -- -D warnings

  # 3. Remove unused dependencies (requires nightly)
  if has cargo-udeps; then
    log "Checking for unused dependencies..."
    run cargo +nightly udeps --all-targets 2>/dev/null || :
  fi
  has cargo-shear && run cargo shear || :

  # 4. Find dead code
  has cargo-machete && { log "Finding dead code..."; run cargo machete || :; }

  # 5. Asset optimization (if not skipped)
  if ((! SKIP_ASSETS)); then
    # Minify HTML
    if has minhtml; then
      log "Minifying HTML..."
      while IFS= read -r f; do
        run minhtml -i "$f" -o "$f"
      done < <(find_files "*.html")
    fi

    # Optimize images
    if [[ -d assets ]]; then
      log "Optimizing images..."
      has oxipng && while IFS= read -r f; do run oxipng -o 4 -q "$f"; done < <(find_files "*.png" assets)
      has jpegoptim && while IFS= read -r f; do run jpegoptim --strip-all -q "$f"; done < <(find_files "*.jpg" assets)
    fi

    # Compress static assets
    has flaca && [[ -d static ]] && { log "Compressing static assets..."; run flaca compress ./static || :; }
  fi

  # 6. Clean workspace cruft
  has cargo-diet && run cargo diet || :

  # 7. Lint features/deps
  has cargo-unused-features && run cargo unused-features || :
  has cargo-duplicated-deps && run cargo duplicated-deps || :

  # 8. Final format & lint
  log "Final format pass..."
  run cargo fmt
  run cargo clippy -- -D warnings

  # 9. Build release
  log "Building release..."
  run cargo build --release

  # 10. Strip binary
  local bin="target/release/${PWD##*/}"
  if [[ -f $bin ]]; then
    log "Stripping binary..."
    run strip "$bin"
    ls -lh "$bin"
  fi

  log "${GRN}Done${DEF}"
}

main "$@"
