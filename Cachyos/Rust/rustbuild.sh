#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
LC_ALL=C
export RUSTFLAGS="-C opt-level=3 -C lto -C codegen-units=1 -C target-cpu=native -C linker=clang -C link-arg=-fuse-ld=mold -C panic=abort -Zno-embed-metadata"

# Update & audit deps
cargo update
cargo outdated

# Format & lint
cargo fmt
cargo clippy -- -D warnings

# 1. Detect & remove unused dependencies
cargo +nightly install cargo-udeps cargo-shear
cargo udeps --all-targets
cargo shear

# 2. Find dead code / unused items
cargo machete

# 3. Minify HTML
find . -name "*.html" -exec minhtml -i {} -o {} \;

# 4. Optimize images
find assets -type f \( -iname '*.png' -o -iname '*.jpg' \) -exec rimage {} --optimize \;
find assets -type f -name '*.png' -exec oxipng -o 4 {} \;
find assets -type f -name '*.jpg' -exec jpegoptim --strip-all {} \;

# 5. Compress arbitrary assets (fonts, maps, wasm, json, etc.)
flaca compress ./static

# 6. Remove unneeded workspace cruft
cargo diet

# 7. Lint features and dep versions
cargo unused-features
cargo duplicated-deps

# 8. Sort & normalize
cargo sort-fix

# Format & lint
cargo fmt
cargo clippy -- -D warnings

# 9. Parallel compile (faster dev cycle)
cargo q build --release # if you installed cargo-q

# 10. PGO compile
cargo pgo build --bin your_app

# 11. Strip and report size
strip target/release/"${PWD##*/}"
ls -lh target/release/"${PWD##*/}"
