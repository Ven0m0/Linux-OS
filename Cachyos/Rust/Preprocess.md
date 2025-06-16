# Tools/commannds for preprocessing a crate before installing it

### Rustflags:
```
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C strip=symbols -C lto=on -C embed-bitcode=yes -Z dylib-lto -Z default-visibility=hidden -Z tune-cpu=native"
```

### Fix and clean for the crate before build/install
```
cargo update --recursive
cargo fix --workspace --all-targets --all-features -r --bins --allow-dirty
cargo clippy --fix --allow-dirty --allow-staged
cargo-shear --fix --expand
cargo-machete --fix --with-metadata && cargo-machete --fix
cargo-diet diet
cargo-cache -g -f -e clean-unref
cargo install --profile release --path .
```
