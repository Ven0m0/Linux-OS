# Install rustup
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly
```

### Minimal nightly
```
rustup default nightly && rustup set profile minimal && rustup set default-host x86_64-unknown-linux-gnu
```

### Minimal stable
```
rustup default stable && rustup set profile minimal && rustup set default-host x86_64-unknown-linux-gnu
```

### Some componements commonly required
```
rustup component add llvm-tools-x86_64-unknown-linux-gnu llvm-bitcode-linker-x86_64-unknown-linux-gnu clippy-x86_64-unknown-linux-gnu rust-std-wasm32-unknown-unknown rust-std-wasm32-wasip2
```
