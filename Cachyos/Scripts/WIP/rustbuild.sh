#!/usr/bin/env bash
set -euo pipefail

# 1. Detect & remove unused dependencies
cargo +nightly install cargo-udeps cargo-shear
cargo udeps --all-targets
cargo shear                         # removes unused deps from Cargo.toml

# 2. Find dead code / unused items
cargo machete                      # (optional) remove unused public functions

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
cargo outdated

# 8. Sort & normalize
cargo sort-fix

# 9. Parallel compile (faster dev cycle)
cargo q build --release            # if you installed cargo-q

# 10. PGO compile
cargo pgo build --bin your_app

# 11. Strip and report size
strip target/release/$(basename $(pwd))
ls -lh target/release/$(basename $(pwd))
