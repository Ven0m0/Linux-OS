#Todo

https://github.com/vasi/pixz

https://crates.io/crates/protonup-rs

https://crates.io/crates/cargo-sleek

https://crates.io/crates/du-dust

https://crates.io/crates/fd-find

https://crates.io/crates/brush-shell

cargo install nexish

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

cargo-unused-features
cargo install rustscout-cli
cargo install dedups
cargo install argc

cargo install redlib

cargo install teip

cargo install shim
cargo install shimexe

cargo install flash

# ls
https://crates.io/crates/lla

https://crates.io/crates/mc-repack

https://crates.io/crates/touch-cli

cargo install less


https://crates.io/crates/hitdns
https://github.com/jedisct1/EtchDNS

https://github.com/macp3o/linux-tweaks

https://gitlab.com/iucode-tool/iucode-tool/-/wikis/home
https://github.com/AnnikaV9/kbuilder
https://crates.io/crates/vicut

# Dotfiles

```markdown
https://github.com/milobanks/greatness
https://github.com/SuperCuber/dotter
https://github.com/oknozor/toml-bombadil
https://github.com/volllly/rotz
https://github.com/freshshell/fresh
https://crates.io/crates/ldfm
https://crates.io/crates/dfm
https://github.com/Addvilz/dots
https://github.com/comtrya/comtrya
https://github.com/RaphGL/Tuckr
https://github.com/elkowar/yolk
https://github.com/deadc0de6/dotdrop
```

```
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
-Zbuild-std=std,panic_abort
-Zbuild-std-features=panic_immediate_abort

-Z build-std-features=panic_immediate_abort,compiler-builtins-mem
-Z build-std=core,alloc,std,panic_abort,compiler_builtins

-Z build-std=std,panic_abort,compiler_builtins -Zbuild-std-features=panic_immediate_abort,compiler-builtins-mem

-Z cargo-lints

RUSTFLAGS="-C llvm-args=-polly -C llvm-args=-polly-vectorizer=polly"

-Z llvm-plugins=LLVMPolly.so
-Z llvm-plugins=/usr/lib/LLVMPolly.so
-C llvm-args=-polly-vectorizer=stripmine

export PYTHONOPTIMIZE=2

export BUILDCACHE_COMPRESS_FORMAT=ZSTD
export BUILDCACHE_COMPRESS_FORMAT=LZ4
export BUILDCACHE_ACCURACY=SLOPPY
export BUILDCACHE_ACCURACY=DEFAULT
export BUILDCACHE_DIRECT_MODE=true
export CCACHE_COMPRESS=true
export CCACHE_COMPRESSLEVEL=3
export CCACHE_INODECACHE=true

Codegen:
-Z precise-enum-drop-elaboration=yes
PGO:
-Z debug-info-for-profiling

```
```
git tweaks
git clone --depth 1 --single-branch --shallow-submodules --filter='blob:none'
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
```
sudo sysctl -q kernel.perf_event_paranoid="$orig_perf"
echo "$orig_kptr" | sudo tee /proc/sys/kernel/kptr_restrict >/dev/null
echo "$orig_turbo" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null

sync;echo 3 | sudo tee /proc/sys/vm/drop_caches

echo within_size | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled
echo 1 | sudo tee /sys/kernel/mm/ksm/use_zero_pages

echo 1 | sudo tee /proc/sys/kernel/perf_event_paranoid >/dev/null

mount -o remount,huge=within_size /mountpoint

sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid" # 2

sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space"
sudo sh -c "echo 0 > /proc/sys/kernel/nmi_watchdog" || (sudo sysctl -w kernel.nmi_watchdog=0)
sudo sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo"
sudo sh -c "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo"

cargo pgo test
cargo pgo run

CFLAGS="${CFLAGS/-O2/-O3}"
export CFLAGS="${CFLAGS} -fprofile-generate -fprofile-update=atomic -fprofile-partial-training"


export CMAKE_BUILD_TYPE=Release
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=clang
export HOSTS=x86_64-unknown-linux-gnu


_python_optimize() {
  python -m compileall "$@"
  python -O -m compileall "$@"
  python -OO -m compileall "$@"
}


cargo pgo build
cargo pgo run
cargo pgo test
cargo pgo bench
```
```
# Export CARGO_HOME and RUSTUP_HOME for Rust
export CARGO_HOME="${HOME}/.cargo"
export RUSTUP_HOME="${HOME}/.rustup"

# Force Firefox to use Wayland protocol and not XWayland
export MOZ_ENABLE_WAYLAND=1

# Silence macOS warning about zsh
export BASH_SILENCE_DEPRECATION_WARNING=1

if [ -d "${HOME}/bin" ] ; then PATH="${PATH}:${HOME}/bin" ; fi

# add Rust path
if [ -e "$HOME/.cargo/bin" ]; then
  PATH="${HOME}/.cargo/bin:${PATH}"
fi

# Add path to ~/.local/bin for aws cli on linux
if [ -d "${HOME}/.local/bin" ] ; then PATH="${HOME}/.local/bin:${PATH}" ; fi

export PATH

# remove duplicates from PATH, even though the
# shell will only use the first occurrance.
# https://www.linuxjournal.com/content/removing-duplicate-path-entries
PATH=$(echo "$PATH" | awk -v RS=: '!($0 in a) {a[$0]; printf("%s%s", length(a) > 1 ? ":" : "", $0)}')
export PATH


if command -v bat &>/dev/null; then
    alias cat='bat -pp'
fi
if command -v zoxide &>/dev/null; then
     eval "$(zoxide init bash)"
     alias cd='z'
     alias cdd='z -'
fi
if command -v fzf &>/dev/null; then
    
fi
cargo install pfetch
cargo install imgc
cargo install rust-dns
cargo install soar-cli
cargo install ripuniq
cargo install rmrfrs
cargo install fdf
cargo install fecr
cargo install minhtml
cargo install rustminify-cli
cargo install oxipng
cargo install cargo-sleek
cargo install webcomp
https://codeberg.org/TotallyLeGIT/doasedit
```

Twaks todo:

```bash
sudo nano /usr/lib/tmpfiles.d/pcie_aspm_performance.conf
w /sys/module/pcie_aspm/parameters/policy - - - - performance

sudo nano /usr/lib/tmpfiles.d/cpu-governor.conf
w /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor - - - - performance

sudo nano /usr/lib/tmpfiles.d/energy_performance_preference.conf
w /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference - - - - performance
```
