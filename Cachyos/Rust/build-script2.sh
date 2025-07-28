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

# 4. Compress images
find assets -type f \( -iname '*.png' -o -iname '*.jpg' \) -exec rimage {} --optimize \;

# 5. Compress arbitrary assets (fonts, maps, wasm, json, etc.)
flaca compress ./static

# 6. Remove unneeded workspace cruft
cargo diet -p your_crate_name      # shows what will ship → trim as needed

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
