# Tools/commannds for preprocessing a crate before installing it


```
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C strip=symbols -C lto=on -C embed-bitcode=yes -Z dylib-lto -Z default-visibility=hidden -Z tune-cpu=native -C target-feature=+avx2,+fma,+sse4.2,+aes,+prefetchi,+branch-hint"
cargo update --recursive
cargo-shear --fix --expand
cargo-diet diet
cargo-cache -g -f -e clean-unref
cargo install --profile release --path 'projectpath'
```
