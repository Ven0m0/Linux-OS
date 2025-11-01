### Install rustup  
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy,rustc-dev -t x86_64-unknown-linux-gnu,wasm32-unknown-unknown -y
```
### Minimal install
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -y
```  
### Minimal nightly  
```bash
rustup default nightly && rustup set profile minimal && rustup set default-host x86_64-unknown-linux-gnu
```  
### Minimal stable  
```bash
rustup default stable && rustup set profile minimal && rustup set default-host x86_64-unknown-linux-gnu
```

### Some componements commonly required  
```bash
rustup component add llvm-tools-x86_64-unknown-linux-gnu llvm-bitcode-linker-x86_64-unknown-linux-gnu clippy-x86_64-unknown-linux-gnu rust-std-wasm32-unknown-unknown rust-std-wasm32-wasip2
```

<details>
<summary><b>Flags:</b></summary>

```bash
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat -Cembed-bitcode -Zunstable-options -Zdylib-lto -Zdefault-visibility=hidden -Ztune-cpu=native -Cpanic=abort -Zprecise-enum-drop-elaboration=yes -Zno-embed-metadata -Clink-arg=-fuse-ld=mold -Clink-arg=-flto -Cllvm-args=-enable-dfa-jump-thread"
```

Safe RUSTFLAGS:

```bash
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat -Clinker-plugin-lto -Clink-arg=-fuse-ld=mold -Cpanic=abort -Zunstable-options -Ztune-cpu=native -Cllvm-args=-enable-dfa-jump-thread -Zfunction-sections -Zfmt-debug=none -Zlocation-detail=none" OPT_LEVEL=3 CARGO_INCREMENTAL=0 RUSTC_BOOTSTRAP=1 RUSTUP_TOOLCHAIN=nightly
```
```bash
LC_ALL=C cargo +nightly -Zgit -Zgitoxide -Zno-embed-metadata -Zbuild-std=std,panic_abort -Zbuild-std-features=panic_immediate_abort install 
```

```bash
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Zunstable-options -Ztune-cpu=native -Cpanic=abort -Cllvm-args=-enable-dfa-jump-thread"
```

```Linkers
-Clink-arg=-fuse-ld=lld
-Clink-arg=-fuse-ld=mold
```

**Full std build**
```bash
export RUSTC_BOOTSTRAP=1 CARGO_INCREMENTAL=0 OPT_LEVEL=3 CARGO_PROFILE_RELEASE_LTO=true CARGO_CACHE_RUSTC_INFO=1 RUSTC_WRAPPER=sccache
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat -Clinker-plugin-lto -Clink-arg=-fuse-ld=mold -Cllvm-args=-enable-dfa-jump-thread -Cpanic=immediate-abort -Zunstable-options -Ztune-cpu=native -Zfunction-sections -Zfmt-debug=none -Zlocation-detail=none -Zprecise-enum-drop-elaboration=yes -Zdefault-visibility=hidden"
cargo +nightly -Zunstable-options -Zavoid-dev-deps -Zbuild-std=std,panic_abort -Zbuild-std-features=panic_immediate_abort install -f 
```

```bash
export CFLAGS="-march=native -mtune=native -O3 -pipe -fno-plt -Wno-error \
  -fno-semantic-interposition -fdata-sections -ffunction-sections -ftree-vectorize \
	-fomit-frame-pointer -fvisibility=hidden -fmerge-all-constants -finline-functions \
  -fjump-tables -pthread -fshort-enums -fshort-wchar -feliminate-unused-debug-types -feliminate-unused-debug-symbols"
```
```bash
export CXXFLAGS="$CFLAGS -fsized-deallocation -fstrict-vtable-pointers"
```
```bash
export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now \
         -Wl,-z,pack-relative-relocs -Wl,-gc-sections -Wl,--compress-relocations \
         -Wl,--discard-locals -Wl,--strip-all -Wl,--icf=all"
```

</details>


# Rust apps/resources

### [Crates.io rust projects](https://crates.io)

### [Lib.rs rust apps](https://lib.rs)

### [Rust libhunt](https://rust.libhunt.com)

### [Min-sized-rust](https://github.com/johnthagen/min-sized-rust)

### [Std aware cargo](https://github.com/rust-lang/wg-cargo-std-aware)

# Learn Rust

### [Rustlings](https://rustlings.rust-lang.org)

### [Rust-learning](https://github.com/ctjhoa/rust-learning)
