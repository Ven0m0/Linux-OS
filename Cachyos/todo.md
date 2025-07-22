
https://crates.io/crates/quicssh-rs

https://github.com/vasi/pixz

https://crates.io/crates/protonup-rs

https://crates.io/crates/bcmr

https://crates.io/crates/cargo-sleek

https://crates.io/crates/du-dust

https://crates.io/crates/rsftch

https://crates.io/crates/fd-find

https://crates.io/crates/ohcrab

https://crates.io/crates/brush-shell

https://crates.io/crates/boltshell

https://gitlab.redox-os.org/redox-os/ion/

https://wiki.archlinux.org/title/List_of_applications/Documents#Console

https://wiki.archlinux.org/title/List_of_applications/Internet#Firefox_spin-offs


https://www.commandlinefu.com/commands/browse

https://wiki.archlinux.org/title/Secure_Shell

https://wiki.archlinux.org/title/Display_manager

https://wiki.archlinux.org/title/Domain_name_resolution#DNS_servers

https://wiki.archlinux.org/title/Domain_name_resolution


https://github.com/Kobzol/cargo-pgo/blob/main/README.md

https://crates.io/crates/rocketfetch

https://crates.io/crates/hitdns

https://crates.io/crates/cargo-unused-features

# ls
https://crates.io/crates/lla

https://crates.io/crates/mc-repack

https://crates.io/crates/touch-cli

cargo install less


# https://crates.io/crates/hitdns
cargo install hitdns

# https://github.com/jedisct1/EtchDNS

https://github.com/macp3o/linux-tweaks

# Dotfiles

```markdown
https://github.com/milobanks/greatness
https://github.com/SuperCuber/dotter
https://github.com/oknozor/toml-bombadil
https://github.com/volllly/rotz
https://github.com/plamorg/ambit
https://crates.io/crates/ldfm
https://crates.io/crates/dfm
https://github.com/Addvilz/dots
https://github.com/comtrya/comtrya
https://github.com/RaphGL/Tuckr
https://github.com/elkowar/yolk


https://github.com/644/compressimages
https://github.com/jkool702/forkrun
https://crates.io/crates/trees-rs
fisher install meaningful-ooo/sponge
fisher install acomagu/fish-async-prompt
```

```markdown
ARCH="$(uname -m)"
SHELL=/usr/bin/bash

Cargo:
-Z avoid-dev-deps -Z no-embed-metadata -Z trim-paths

Full lto:
-Z build-std=std,panic_abort
-Z build-std-features

-Z cargo-lints

Rustc:
-Z relax-elf-relocations -Z checksum-hash-algorithm=blake3 -Z fewer-names -Z combine-cgu
-Z mir-opt-level=4 / 3
-Z packed-bundled-libs
-Z function-sections
-Z min-function-alignment=64

RUSTFLAGS="-C llvm-args=-polly -C llvm-args=-polly-vectorizer=polly"


export PYTHONOPTIMIZE=2

export BUILDCACHE_COMPRESS_FORMAT=ZSTD
export BUILDCACHE_COMPRESS_FORMAT=LZ4
export BUILDCACHE_ACCURACY=SLOPPY
export BUILDCACHE_ACCURACY=DEFAULT
export BUILDCACHE_DIRECT_MODE=true


PGO:
-Z debug-info-for-profiling


```
```markdown
Rust tls models:
-Z tls-model=initial-exec
# Fallback
-Z tls-model=local-dynamic
# fastest if no dynamic libs
-Z tls-model=local-exec 
```
```
LC_MEASUREMENT=metric
LC_COLLATE=C
LC_CTYPE=C.UTF-8

curl ifconfig.me

rust-parallel -d stderr -j16
-p, --progress-bar
PROGRESS_STYLE=dark_bg
PROGRESS_STYLE=simple
```
```
rust-parallel -d stderr -j16
-p, --progress-bar
PROGRESS_STYLE=dark_bg
PROGRESS_STYLE=simple
```
```
# Build only minimal debug info to reduce size
CFLAGS=${CFLAGS/-g /-g0 }
CXXFLAGS=${CXXFLAGS/-g /-g0 }
# Add fno-semantic-position, can improve at fPIC compiled packages massively the performance
export CFLAGS+=" -fno-semantic-interposition"
export CXXFLAGS+=" -fno-semantic-interposition"
```
## PGO
```
# define PGO_PROFILE_DIR to use a custom directory for the profile data
export PGO_PROFILE_DIR=$PWD/pgo

# clean up the profile data
mkdir -p ${PGO_PROFILE_DIR}
rm -f ${PGO_PROFILE_DIR}/*

# append -Cprofile-generate=/tmp/pgo-data to the rustflags
export RUSTFLAGS+=" -Cprofile-generate=${PGO_PROFILE_DIR}"

# run the benchmark
hyperfine --warmup 5 --min-runs 10

# run the tests
cargo test
cargo pgo run

# remove -Cprofile-generate=${PGO_PROFILE_DIR} from the rustflags
export RUSTFLAGS=${RUSTFLAGS//-Cprofile-generate=${PGO_PROFILE_DIR}/}
export RUSTFLAGS=$(echo $RUSTFLAGS | sed -e 's/-Cprofile-generate=\/tmp\/pgo-data//')

export RUSTFLAGS=${RUSTFLAGS//-Cprofile-generate=${PGO_PROFILE_DIR}/}

# merge the profile data
llvm-profdata merge -o ${PGO_PROFILE_DIR}/merged.profdata ${PGO_PROFILE_DIR}

# append -Cprofile-use=/tmp/pgo-data to the rustflags
export RUSTFLAGS+=" -Cprofile-use=${PGO_PROFILE_DIR}/merged.profdata"

cargo build -r
```
