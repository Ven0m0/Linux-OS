# Todo

- <https://wiki.archlinux.org/title/List_of_applications/Documents#Console>
- <https://wiki.archlinux.org/title/List_of_applications/Internet#Firefox_spin-offs>
- <https://www.commandlinefu.com/commands/browse>
- <https://wiki.archlinux.org/title/Domain_name_resolution>
- <https://github.com/macp3o/linux-tweaks>
- <https://github.com/644/compressimages>

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

```bash
git clone --depth 1--shallow-submodules --filter='blob:none'
```

## PGO

```bash
RUSTFLAGS="-C llvm-args=-polly -C llvm-args=-polly-vectorizer=stripmine -Zllvm-plugins=/usr/lib/LLVMPolly.so"
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

sudo sysctl -q kernel.perf_event_paranoid="$orig_perf"
echo "$orig_kptr" | sudo tee /proc/sys/kernel/kptr_restrict >/dev/null
echo "$orig_turbo" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null

sync;echo 3 | sudo tee /proc/sys/vm/drop_caches

echo within_size | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled
echo 1 | sudo tee /sys/kernel/mm/ksm/use_zero_pages

echo 1 | sudo tee /proc/sys/kernel/perf_event_paranoid >/dev/null

sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid" # 2

sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space"
sudo sh -c "echo 0 > /proc/sys/kernel/nmi_watchdog" || (sudo sysctl -w kernel.nmi_watchdog=0)
sudo sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo"
sudo sh -c "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo"

CFLAGS="${CFLAGS/-O2/-O3}"
export CFLAGS="${CFLAGS} -fprofile-generate -fprofile-update=atomic -fprofile-partial-training"

_python_optimize() {
  python -m compileall "$@"
  python -O -m compileall "$@"
  python -OO -m compileall "$@"
}


cargo pgo build
cargo pgo run
cargo pgo test
cargo pgo bench

# Export CARGO_HOME and RUSTUP_HOME for Rust
export CARGO_HOME="${HOME}/.cargo"
export RUSTUP_HOME="${HOME}/.rustup"

# Add path to ~/.local/bin for aws cli on linux
if [ -d "${HOME}/.local/bin" ] ; then PATH="${HOME}/.local/bin:${PATH}" ; fi

# remove duplicates from PATH, even though the
# shell will only use the first occurrance.
# https://www.linuxjournal.com/content/removing-duplicate-path-entries
PATH=$(echo "$PATH" | awk -v RS=: '!($0 in a) {a[$0]; printf("%s%s", length(a) > 1 ? ":" : "", $0)}')
export PATH

cargo install pfetch
cargo install imgc
cargo install rmrfrs
cargo install fecr
cargo install rustminify-cli
cargo install cargo-sleek
cargo install webcomp
https://codeberg.org/TotallyLeGIT/doasedit
```

- Java:

- <https://www.graalvm.org/22.2/reference-manual/native-image/guides/optimize-native-executable-with-pgo>

- <https://www.graalvm.org/22.2/reference-manual/native-image/optimizations-and-performance/MemoryManagement>

- <https://github.com/XDream8/kiss-repo/blob/main/bin/openjdk17-jdk/build>

- <https://gitlab.com/arkboi/dotfiles>

- <https://lancache.net>

- <https://github.com/XDream8/kiss-repo/blob/main/core/mawk/build>

- <https://github.com/DanielFGray/fzf-scripts>

- <https://crates.io/crates/autokernel>

- <https://crates.io/crates/cargo-trim>

- <https://crates.io/crates/cargo-unused-features>

- cargo install config-edit

- <https://github.com/Toqozz/wired-notify>
