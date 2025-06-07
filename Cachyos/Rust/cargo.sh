https://crates.io/crates

cargo +nightly build --release 


cargo install cargo-shear
cargo shear --fix
cargo shear --expand --fix

##  Mimalloc
cargo add mimalloc-safe
# in main.rs
use mimalloc_safe::MiMalloc;

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

# Rayon parallel
https://crates.io/crates/rayon
cargo add rayon
foo.iter() ---> foo.par_iter()


# Fastant tsc optimization
https://crates.io/crates/fastant
cargo add fastant
#in main.rs
fn main() {
    let start = fastant::Instant::now();
    let duration: std::time::Duration = start.elapsed();
}


# parking_lot: More compact and efficient implementations of the standard synchronization primitives
# https://crates.io/crates/parking_lot
# wasm32-unknown-unknown --> only on nightly with "-C target-feature=+atomics"  in RUSTFLAGS and -Zbuild-std=panic_abort,std passed to cargo
cargo add parking_lot
#in cargo.toml:
[dependencies]
parking_lot = { version = "*", features = ["nightly", "deadlock_detection"] }
parking_lot = { version = "*", features = ["nightly", "send_guard"] }
# Note that the deadlock_detection and send_guard features are incompatible and cannot be used together.

# Hashbrown: Google's high-performance SwissTable hash map
# https://crates.io/crates/hashbrown
cargo add hashbrown
#in main.rs
use hashbrown::HashMap;

let mut map = HashMap::new();
map.insert(1, "one");

#in cargo.toml:
hashbrown = { version = "*", features = ["nightly", "rayon", "inline-more"] }


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

# Rust-curl
https://crates.io/crates/rust-curl
cargo install rust-curl
#Compile Rusr-curl
git clone https://github.com/arvid-berndtsson/rurl.git
cd rurl
cargo build --release && cargo install --path .


# Better fastfetch
cargo install rustch

# Fast, hardware-accelerated CRC calculation
cargo install crc-fast
cargo +nightly build --release --features=optimize_crc32_auto,vpclmulqdq

# Better pigz
cargo install crabz

# Better sed
https://crates.io/crates/sd
cargo install sd


