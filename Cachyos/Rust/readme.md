# Rust Tools and Optimization Scripts

This directory contains scripts and documentation for working with Rust, including advanced build optimizations, PGO/BOLT profiling, and Rust replacements for GNU utilities.

## Scripts

### cargo-build.sh

**Unified Rust build script with PGO/BOLT optimization support**

A comprehensive build script that consolidates features from multiple optimization scripts. Supports:

- Standard cargo build and install operations
- Profile-Guided Optimization (PGO) in two phases: instrumentation and optimization
- Binary Optimization and Layout Tool (BOLT) for additional performance gains
- Advanced compiler flags and linker options (mold, lld)
- Git cleanup and project maintenance
- sccache integration for faster builds

**Usage:**

```bash
# Install optimized crates
./cargo-build.sh --install ripgrep fd bat

# Build with PGO instrumentation
./cargo-build.sh --pgo 1

# Build with PGO optimization (after profiling)
./cargo-build.sh --pgo 2

# Build with PGO + BOLT
./cargo-build.sh --pgo 2 --bolt

# Install with mold linker
./cargo-build.sh --install --mold eza
```

### rustify.sh

**System-wide Rust utility installation script**

Installs Rust replacements for GNU utilities and system tools, including:

- uutils-coreutils, diffutils, findutils, procps, tar, sed
- Modern alternatives: ripgrep, fd, dust, cpz/rmz, etc.
- update-alternatives setup for Arch Linux
- oxidizr-arch for automatic Rust utility adoption

**Warning:** This script makes system-wide changes. Review before running.

**Note:** rustify.sh includes binary stripping functionality with `strip -sx` to reduce file sizes.

## Documentation

### readme.md (this file)

Overview and guide for the Rust directory.

### wip.txt

**Comprehensive reference for Rust optimization flags**

Contains:

- RUSTFLAGS for various optimization levels
- PGO and BOLT workflow documentation
- C/C++ compiler flags (CFLAGS, CXXFLAGS, LDFLAGS)
- Environment variable configurations
- Cargo maintenance commands
- Useful project links

### Preprocess.md

**Preprocessing tools for Rust crates**

Documentation on tools and commands for preprocessing and optimizing crates before building:

- Code minification tools (rustminify, minhtml)
- Dependency cleanup (cargo-shear, cargo-machete)
- Asset optimization workflows

### Rust-atlernatives.txt

**Extensive list of Rust alternatives and tools**

A curated list of Rust crates organized by category:

- Cargo utilities and extensions
- System utilities (coreutils replacements)
- Search tools (ripgrep, fd, etc.)
- File management and compression
- Network utilities
- Editors and terminals
- And much more...

## Quick Start

### Install Rustup (Minimal Nightly)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -y
rustup default nightly
rustup set profile minimal
rustup set default-host x86_64-unknown-linux-gnu
```

### Common Components

```bash
rustup component add llvm-tools-x86_64-unknown-linux-gnu llvm-bitcode-linker-x86_64-unknown-linux-gnu clippy-x86_64-unknown-linux-gnu
```

### Build with Optimizations

For quick optimized builds:

```bash
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat -Cpanic=abort -Zunstable-options -Ztune-cpu=native"
export RUSTC_BOOTSTRAP=1
cargo +nightly build --release
```

For advanced PGO/BOLT optimizations, use the `cargo-build.sh` script.

## Optimization Levels

### Level 1: Basic Optimizations (Fast)

```bash
RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Cstrip=symbols"
cargo build --release
```

### Level 2: Advanced Optimizations (Recommended)

```bash
./cargo-build.sh --build
```

Uses LTO, native CPU tuning, aggressive inlining, and more.

### Level 3: PGO (Profile-Guided Optimization)

```bash
# Phase 1: Instrument
./cargo-build.sh --pgo 1

# Run workload to collect profiles
./target/release/binary <typical-workload>

# Merge profiles
llvm-profdata merge -output=default.profdata ./pgo_data

# Phase 2: Optimize
./cargo-build.sh --pgo 2
```

### Level 4: PGO + BOLT (Maximum Performance)

```bash
# Run PGO phases first, then:
./cargo-build.sh --pgo 2 --bolt

# Run instrumented binary
./target/release/binary-bolt-instrumented <workload>

# Finalize BOLT optimization
cargo pgo bolt optimize --with-pgo
```

## Performance Tips

1. **Use sccache** for faster recompilation:

   ```bash
   cargo install sccache
   export RUSTC_WRAPPER=sccache
   ```

1. **Parallel builds**:

   ```bash
   export CARGO_BUILD_JOBS=$(nproc)
   ```

1. **Use modern linker** (mold or lld):

   ```bash
   ./cargo-build.sh --install --mold <crate>
   ```

1. **Clean unused dependencies regularly**:

   ```bash
   cargo install cargo-shear cargo-machete cargo-cache
   cargo-shear --fix
   cargo-machete --fix
   cargo-cache -g -f -e clean-unref
   ```

## Resources

### Official Documentation

- [The Rust Performance Book](https://nnethercote.github.io/perf-book/)
- [Min-sized Rust](https://github.com/johnthagen/min-sized-rust)
- [Cargo std-aware](https://github.com/rust-lang/wg-cargo-std-aware)

### Package Registries

- [Crates.io](https://crates.io) - Official Rust package registry
- [Lib.rs](https://lib.rs) - Alternative Rust package index
- [Rust Libhunt](https://rust.libhunt.com) - Trending Rust projects

### Learning

- [Rustlings](https://rustlings.rust-lang.org) - Interactive Rust exercises
- [Rust Learning](https://github.com/ctjhoa/rust-learning) - Curated learning resources

## Notes

- All scripts assume a Linux environment with sudo access
- PGO/BOLT require collecting runtime profiles, so use representative workloads
- Some optimization flags are unstable and require nightly Rust
- Always test optimized binaries thoroughly before deploying

## Contributing

When adding new scripts or optimizations:

1. Document usage and purpose clearly
1. Test on multiple Rust versions (stable and nightly)
1. Include performance comparisons where relevant
1. Update this README with any new additions
