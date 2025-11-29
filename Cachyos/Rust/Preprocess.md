## Tools/commannds for preprocessing a crate before installing it

### Rustflags

```bash
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat -Cembed-bitcode=yes -Zunstable-options -Zdylib-lto -Zdefault-visibility=hidden -Ztune-cpu=native -Cpanic=abort -Zprecise-enum-drop-elaboration=yes -Zlocation-detail=none -Crelro-level=off -Zno-embed-metadata -Clinker=clang -Clink-arg=-fuse-ld=lld -Cllvm-args=-enable-dfa-jump-thread"
```

Other flags

```bash
export CFLAGS="-march=native -mtune=native -O3 -pipe -fno-plt -Wno-error \
         -fno-semantic-interposition -fdata-sections -ffunction-sections \
         -fbasic-block-sections=all -fjump-tables -pthread -fomit-frame-pointer \
         -fvisibility=hidden -fmerge-all-constants -finline-functions"
```

### Fix and clean for the crate before build/install

```bash
cargo update --recursive
cargo fix --workspace --all-targets --all-features -r --bins --allow-dirty
cargo clippy --fix --allow-dirty --allow-staged
cargo-shear --fix --expand
cargo-machete --fix --with-metadata && cargo-machete --fix
cargo-diet diet
cargo-cache -egf
if command -v fd &>/dev/null; then
  fd -tf -e rs . -x rustminify --remove-docs {}
else
  find -O3 . -type f -name "*.rs" -exec rustminify --remove-docs {} \;
fi
if command -v fd &>/dev/null; then
  fd -tf -e html -e js -e css . -x minhtml --minify-js --minify-css --minify-css-level-2 --remove-bangs \
    --keep-closing-tags --keep-spaces-between-attributes --ensure-spec-compliant-unquoted-attribute-values {}
else
  find -O3 . -type f \( -name "*.html" -o -name "*.js" -o -name "*.css" \) -exec minhtml --minify-js --minify-css --minify-css-level-2 --remove-bangs \
    --keep-closing-tags --keep-spaces-between-attributes --ensure-spec-compliant-unquoted-attribute-values {} \;
fi
pitufo --minify -m 10 -p "$PWD"
cg-bundler --pretty --m2 --validate --debounce 250 || cg-bundler --pretty -m --validate --debounce 250
```

**Install deps**

```bash
cargo install minhtml
cargo install rustminify-cli
cargo install pitufo
cargo install cg-bundler
```

### LLVM args

```bash
-Cllvm-args=-enable-dfa-jump-thread -Cllvm-args=-enable-misched -Cllvm-args=-enable-gvn-hoist -Cllvm-args=-enable-gvn-sink -Cllvm-args=-enable-loopinterchange -Cllvm-args=-enable-tail-merge
```

experimental:

```bash
-Cllvm-args=-enable-pipeliner
```

pgo

```bash
-Z build-std=std,panic_abort -Z build-std-features=panic_immediate_abort
```

todo"

- <https://crates.io/crates/auto-allocator>
- <https://crates.io/crates/mpatch>
