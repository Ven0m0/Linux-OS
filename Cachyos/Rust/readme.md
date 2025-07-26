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

Flags:

<details>
<summary><b>Flags:</b></summary>

```bash
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C strip=symbols -C lto=on -C embed-bitcode=yes -C relro-level=off -Z tune-cpu=native \
-Z default-visibility=hidden -Z location-detail=none"
```
```bash
export CFLAGS="-march=native -mtune=native -O3 -pipe -fno-plt -Wno-error \
  -fno-semantic-interposition -fdata-sections -ffunction-sections \
	-mprefer-vector-width=256 -ftree-vectorize -fslp-vectorize \
	-fomit-frame-pointer -fvisibility=hidden -fmerge-all-constants -finline-functions \
	-fbasic-block-sections=all -fjump-tables -pthread \
  -falign-functions=32 -falign-loops=32 -malign-branch-boundary=32 -malign-branch=jcc \
	-fshort-enums -fshort-wchar -feliminate-unused-debug-types -feliminate-unused-debug-symbols"
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

 
### Some componements commonly required  
```bash
rustup component add llvm-tools-x86_64-unknown-linux-gnu llvm-bitcode-linker-x86_64-unknown-linux-gnu clippy-x86_64-unknown-linux-gnu rust-std-wasm32-unknown-unknown rust-std-wasm32-wasip2
```

# Rust apps/resources

### [Crates.io rust projects](https://crates.io)

### [Lib.rs rust apps](https://lib.rs)

### [Rust libhunt](https://rust.libhunt.com)

# Learn Rust

### [Rustlings](https://rustlings.rust-lang.org)

### [Rust-learning](https://github.com/ctjhoa/rust-learning)
