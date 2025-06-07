# Tools/commannds for preprocessing a crate before installing it


```
cargo update --recursive
cargo-udeps udeps --release
cargo-shear --fix --expand
cargo-diet diet
cargo-cache -g -f -e clean-unref
```
