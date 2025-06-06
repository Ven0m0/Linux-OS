https://crates.io/crates

cargo +nightly build --release 


cargo install cargo-shear
cargo shear --fix
cargo shear --expand --fix


cargo add mimalloc-safe
# in main.rs
use mimalloc_safe::MiMalloc;

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;


cargo install cargo-clean-all
cargo clean-all -y

cargo install cargo-wasi

# Patch
cargo install cargo-fixup

# System-wide
cargo install cargo-updater
cargo updater

# Per project
cargo install -f cargo-upgrades
cargo upgrades

# See the features of a rust crate
cargo install cargo-whatfeatures
cargo install cargo-whatfeatures --no-default-features --features "rustls"

# LLVM tools from Rust toolchain
cargo install cargo-binutils
rustup component add llvm-tools-preview

# PGO and BOLT to optimize Rust binaries
cargo install cargo-pgo
rustup component add llvm-tools-preview




## Apps

# Dynamic key remapp
cargo install xremap

# Better fastfetch
cargo install rustch

# Fast, hardware-accelerated CRC calculation
cargo install crc-fast
cargo +nightly build --release --features=optimize_crc32_auto,vpclmulqdq
