# Tools/commannds for preprocessing a crate before installing it

### Rustflags:
```
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat -Cembed-bitcode=yes -Zunstable-options -Zdylib-lto -Zdefault-visibility=hidden -Ztune-cpu=native -Cpanic=abort -Zprecise-enum-drop-elaboration=yes -Zno-embed-metadata -Clinker=clang -Clink-arg=-fuse-ld=lld -Cllvm-args=-enable-dfa-jump-thread"
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

### LLVM args
```
-Cllvm-args=-enable-dfa-jump-thread -Cllvm-args=-enable-misched -Cllvm-args=-enable-gvn-hoist -Cllvm-args=-enable-gvn-sink -Cllvm-args=-enable-loopinterchange -Cllvm-args=-enable-tail-merge
```
experimental:
```
-Cllvm-args=-enable-pipeliner
```
