# Copilot Instructions: Linux-OS
## Repo map
- `Cachyos/` Arch-focused setup: `Scripts/` for AIO installers run via curl, `Rust/` for toolchains, `Firefox/` patch sets, top-level `.sh` wrappers for maintenance.
- `RaspberryPi/` imaging and upkeep; `raspi-f2fs.sh` orchestrates loop/partition flows, `Scripts/` hosts Pi automation tasks.
- `Linux-Settings/` holds reference configs (compiler, kernel, shell) consumed by scripts; treat as data sources.
- Root docs (`Shell-book.md`, `Tweaks.txt`, `todo.md`) capture house style and pending work—reuse helpers from there before inventing new ones.

## Bash script template
Start scripts with this canonical structure (adapt from `Shell-book.md` or existing scripts):
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar  # optional but common
export LC_ALL=C LANG=C

# Color & Effects (trans flag palette: LBLU→PNK→BWHT→PNK→LBLU)
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Core helpers (standardize across repo)
has() { command -v "$1" &>/dev/null; }
xecho() { printf '%b\n' "$*"; }
log() { xecho "$*"; }
err() { xecho "$*" >&2; }
die() { err "${RED}Error:${DEF} $*"; exit 1; }

# Privilege escalation (sudo-rs → sudo → doas, store in var)
get_priv_cmd() {
  local cmd
  for cmd in sudo-rs sudo doas; do
    has "$cmd" && { printf '%s' "$cmd"; return 0; }
  done
  [[ $EUID -eq 0 ]] || die "No privilege tool found and not running as root."
}
PRIV_CMD=$(get_priv_cmd)
[[ -n $PRIV_CMD && $EUID -ne 0 ]] && "$PRIV_CMD" -v

run_priv() {
  [[ $EUID -eq 0 || -z $PRIV_CMD ]] && "$@" || "$PRIV_CMD" -- "$@"
}
```

## Code patterns
**Privilege & package managers:**
- Detect privilege with `get_priv_cmd()` searching `sudo-rs`→`sudo`→`doas`; store result and use via `run_priv()`.
- Detect pkg manager: `paru`→`yay`→`pacman` (Arch); fall back to `apt`/`dpkg` (Debian). Store in `pkgmgr` array variable.
- Check existing packages before installing: `pacman -Q pkg`, `flatpak list`, `cargo install --list`.

**Error handling & logging:**
- Define `log()`, `err()`, `die()` functions with colored output (`${RED}Error:${DEF} msg`).
- Add `warn()`, `info()`, `debug()` for verbosity levels as needed (see `archmaint.sh`, `raspi-f2fs.sh`).

**Cleanup & traps:**
- Always use `trap cleanup EXIT INT TERM` with comprehensive cleanup function.
- Cleanup must handle: unmounting (`mountpoint -q && umount`), loop device cleanup (`losetup -d`), lock release (`flock` fd close), temp dir removal.
- Use `|| :` to ignore cleanup errors; log but don't fail.

**Dependency checking:**
- Upfront `check_deps()` function iterating through arrays: `for cmd in "${deps[@]}"; do command -v "$cmd" || warn "Missing: $cmd"; done`.
- Provide distro-specific install hints: `(Arch: pacman -S f2fs-tools)` or `(Debian: sudo apt-get install -y f2fs-tools)`.

**Configuration & dry-run:**
- Use associative arrays for config: `declare -A cfg=([dry_run]=0 [debug]=0 [ssh]=0)`.
- Wrap destructive commands in `run()` function that checks `((cfg[dry_run]))` and logs instead.
- Gate verbose output with `((cfg[debug])) && log "DEBUG: msg" || :`.

**Data collection & processing:**
- Use `mapfile -t arr < <(command)` to avoid subshells; never parse `ls` output.
- Filter package lists: `mapfile -t arr < <(grep -v '^\s*#' file.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')`.
- Check array before iterating: `((${#arr[@]}))` or `[[ ${#arr[@]} -gt 0 ]]`.

**Interactive mode:**
- Support arg-less invocation with fzf selection when `src_path`/`tgt_path` missing.
- Fallback to `find` if `fd` unavailable: `command -v fd &>/dev/null && fd -e img ... | fzf || find ... | fzf`.

**Device & file operations:**
- Use flock for exclusive access: `exec {LOCK_FD}>"/run/lock/script.${path//[^[:alnum:]]/_}"; flock -n "$LOCK_FD" || die "Lock failed"`.
- Derive partition paths with bash pattern matching: `[[ $dev == *@(nvme|mmcblk|loop)* ]] && p="${dev}p1" || p="${dev}1"`.
- Wait for devices with retry loop: `for ((i=0; i<60; i++)); do [[ -b $dev ]] && break; sleep 0.5; done`.

**Build environment (Arch):**
- Export tuned flags (see `Cachyos/Scripts/Install.sh`, `Updates.sh`):
  ```bash
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat"
  export MAKEFLAGS="-j$(nproc)" NINJAFLAGS="-j$(nproc)"
  export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib
  command -v ld.lld &>/dev/null && export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
  ```
- AUR helper flags: `--needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --batchinstall`.

**Network operations:**
- Use hardened curl: `curl -fsSL --proto '=https' --tlsv1.3` for downloads.
- Background long tasks: `curl ... &` and wait/monitor separately.

**ASCII art & banners:**
- Use trans flag gradient palette: `LBLU`→`PNK`→`BWHT`→`PNK`→`LBLU` for banners.
- Colorize line-by-line: `mapfile -t lines <<<"$banner"` then iterate with segment color calculation (see `print_banner()` in `archmaint.sh`, `Updates.sh`).

## Tooling workflow
- Format: `shfmt -i 2 -ci -sr file.sh`; lint: `shellcheck file.sh` (disabled codes in `.shellcheckrc`); harden: run `Harden Script` task.
- Prefer modern tools with fallbacks: `fd`/`find`, `rg`/`grep`, `bat`/`cat`, `sd`/`sed`, `zoxide`/`cd`.
- Use `mktemp -d -p "${TMPDIR:-/tmp}"` for temp dirs; always cleanup in trap.
- Update `README.md` curl snippets when modifying script entrypoints (maintain `curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/...` patterns).
