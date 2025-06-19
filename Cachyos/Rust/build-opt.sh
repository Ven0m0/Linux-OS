#!/bin/bash

export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C strip=symbols -C lto=on -C embed-bitcode=yes -Z dylib-lto -Z tune-cpu=native \
-Z default-visibility=hidden -Z fmt-debug=none -Z location-detail=none -C link-arg=-fomit-frame-pointer -C link-arg=-fno-unwind-tables -C relro-level=off"

cargo +nightly build --release -Z unstable-options -Z gc -Z feature-unification -Z no-embed-metadata -Z avoid-dev-deps
