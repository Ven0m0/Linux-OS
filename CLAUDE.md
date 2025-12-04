# Claude Operating Manual

## Prime Directives
1. **User Primacy:** User commands override all rules.
2. **Factual Verification:** Use tools for versions/APIs. Never guess.
3. **Surgical Modification:** Edit > Create. Minimal line changes. Preserve existing style/logic.
4. **Debt-First:** Remove clutter/deps before adding. Subtraction > Addition.
5. **Autonomous Execution:** Act immediately. Minimize confirmations unless destructive.

## Repository Overview

**Linux-OS** is a collection of shell scripts and configurations for managing Linux distributions, primarily targeting Arch/CachyOS and Debian/Raspberry Pi systems.

### Repository Structure

```
/
├── lib/                    # Core shared libraries
│   ├── core.sh            # Shell settings, colors, logging, helpers
│   ├── arch.sh            # Arch-specific utilities
│   ├── debian.sh          # Debian-specific utilities
│   └── browser.sh         # Browser configuration helpers
├── Cachyos/               # Arch/CachyOS-focused scripts
│   ├── Scripts/           # AIO installers (curlable entrypoints)
│   │   ├── Install.sh     # Automated package installation
│   │   ├── bleachbit.sh   # BleachBit cleaners setup
│   │   ├── bench.sh       # System benchmarking
│   │   └── fstab-tune.sh  # Filesystem optimization
│   ├── Rust/              # Rust toolchain management
│   │   ├── rustbuild.sh   # Rust compilation helpers
│   │   ├── rustify.sh     # Rust optimization scripts
│   │   └── Strip-rust.sh  # Rust binary stripping
│   ├── Firefox/           # Firefox patch sets
│   ├── LLM/               # LLM-related configurations
│   ├── Updates.sh         # System update orchestrator
│   ├── clean.sh           # System cleanup
│   ├── Rank.sh            # Mirror ranking
│   ├── Setup.sh           # Automated configuration
│   ├── archmaint.sh       # Arch maintenance tasks
│   └── debloat.sh         # System debloating
├── RaspberryPi/           # Raspberry Pi specific scripts
│   ├── Scripts/           # Pi automation
│   │   ├── Setup.sh       # Initial Pi setup
│   │   ├── Housekeep.sh   # Maintenance tasks
│   │   ├── Kbuild.sh      # Kernel building
│   │   ├── docker.sh      # Docker setup
│   │   ├── podman.sh      # Podman setup
│   │   └── Nextcloud/     # Nextcloud deployment
│   ├── raspi-f2fs.sh      # F2FS imaging orchestrator
│   ├── update.sh          # Pi update script
│   ├── forward.sh         # Port forwarding
│   ├── PiClean.sh         # Pi cleanup
│   └── dots/              # Dotfiles and configs
├── Linux-Settings/        # Reference configs (compiler, kernel, shell)
├── .github/               # GitHub configuration
│   ├── workflows/         # CI/CD workflows
│   ├── instructions/      # AI assistant instructions
│   ├── prompts/           # Copilot prompts
│   └── agents/            # Agent configurations
├── Shell-book.md          # Bash helpers and patterns
├── USEFUL.MD              # Useful resources and snippets
└── todo.md                # Pending work and TODOs
```

### Target Systems

**Primary:** Arch Linux, CachyOS, Wayland
**Secondary:** Debian, Raspbian, Raspberry Pi OS
**Tertiary:** Termux, EndeavourOS, Gentoo, Nobara, SteamOS, Bazzite

## Communication Style

- **Tone:** Blunt, factual, precise, concise. Technical English.
- **Format:** 2-space indent. No filler. Strip U+202F/U+200B/U+00AD.
- **Output:** Result-first (`Result ∴ Cause`). Group by domain. Lists ≤7 items.
- **Abbrev:** cfg, impl, deps, val, auth, opt, Δ.

### Symbols
→ leads to | ⇒ converts | « / » precedes/follows | ∴ / ∵ therefore/because | ✅ / ❌ success/fail | ⚡ performance | 🛡️ security | 🧪 testing | 📦 deployment | 🔍 analysis

## Bash Standards

### Shebang & Settings
```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
has(){ command -v "$1" &>/dev/null; }
```

### Idioms (Strict)
- **Tests:** `[[ ... ]]`. Regex: `[[ $var =~ ^regex$ ]]`
- **Loops:** `while IFS= read -r line; do ...; done < <(cmd)`. **NO** `for x in $(ls)`
- **Output:** `printf` over `echo`. Capture: `ret=$(fn)`
- **Functions:** `name(){ ... }` (no `function` kw). Nameref: `local -n ref=name`
- **Arrays:** `mapfile -t`. Assoc: `declare -A cfg=([key]=val)`
- **Forbidden:** Parsing `ls`, `eval`, backticks, unnecessary subshells

### Quoting
Always quote variables unless intentional glob/split.

### Privilege & Packages
- **Escalation:** `sudo-rs`→`sudo`→`doas` (store in `PRIV_CMD`)
- **Install:** `paru`→`yay`→`pacman` (Arch); `apt` (Debian)
- **Check first:** `pacman -Q`, `flatpak list`, `cargo install --list`

## Tool Hierarchy (Fallbacks Required)

| Task | Primary | Fallback Chain |
|:---|:---|:---|
| Find | `fd` | `fdfind`→`find` |
| Grep | `rg` | `grep -E` (prefer `-F` for literals) |
| View | `bat` | `cat` |
| Edit | `sd` | `sed -E` |
| Nav | `zoxide` | `cd` |
| Web | `aria2c` | `curl`→`wget2`→`wget` |
| JSON | `jaq` | `jq` |
| Parallel | `rust-parallel` | `parallel`→`xargs -r -P$(nproc)` |

## Core Library (`lib/core.sh`)

### Key Functions
- **has()** - Check if command exists
- **hasname()** - Get command path name
- **xecho()** - Echo with formatting
- **log()/msg()/warn()/err()/die()** - Logging hierarchy
- **dbg()** - Debug logging (enabled by `DEBUG=1`)
- **confirm()** - User confirmation prompt
- **print_banner()** - Trans flag gradient banner
- **find_files()/find0()** - File finding with fallbacks
- **clean_paths()/clean_with_sudo()** - Safe path removal
- **get_download_tool()** - Detect best download tool
- **download_file()** - Download with retry logic
- **capture_disk_usage()** - Disk usage tracking

### Color Palette (Trans Flag)
```bash
LBLU=$'\e[38;5;117m'  # Light blue
PNK=$'\e[38;5;218m'   # Pink
BWHT=$'\e[97m'        # Bright white
DEF=$'\e[0m'          # Reset
BLD=$'\e[1m'          # Bold
```

## Performance

**Measure first. Optimize hot paths.**

- **General:** Batch I/O. Cache computed values. Early returns.
- **Bash:** Minimize forks/subshells. Use builtins. Anchor regexes. Literal search (`grep -F`, `rg -F`).
- **Frontend:** Minimize DOM Δ. Stable keys in lists. Lazy load assets/components.
- **Backend:** Async I/O. Connection pooling. Avoid N+1 queries. Cache hot data (Redis).

## Protected Files

**Do NOT modify unless explicitly requested:**
- `pacman.conf`, `makepkg.conf`, `/etc/sysctl.d/`, `.zshrc`, `.gitconfig`

**Safe zones:** Shell scripts, `.config/`, docs, workflows.

## Development Workflow

### TDD & Atomic Commits
1. **Red:** Write/verify failing test.
2. **Green:** Minimal logic to pass.
3. **Refactor:** Optimize (subtractive design).
4. **Commit:** Single logical unit. Tests pass. No lint errors.
   - Never mix structural (format) and behavioral changes.

### Commit Types
- **Structural:** Format/org changes, no behavior delta
- **Behavioral:** Function add/mod/del
- **NEVER** mix both in one commit

### Quality Gates
- **Linting:** `shellcheck --severity=style` (zero warnings)
- **Formatting:** `shfmt -i 2 -ci -sr`
- **Hardening:** `shellharden --replace` (optional, selective)
- **Testing:** `bats-core` (unit), integration tests (Arch/Debian)
- **Performance:** `hyperfine` for critical paths

## File Operations

- **Edit over create:** Use `str_replace` for existing files.
- **Validation:** Run shellcheck, verify bash syntax before saving.
- **Preserve:** Maintain existing indent, comment style, logic flow.
- **No hidden Unicode:** Strip U+202F, U+200B, U+00AD.
- **No trailing whitespace**

## Script Template

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Colors (trans palette)
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Core helpers
has(){ command -v "$1" &>/dev/null; }
xecho(){ printf '%b\n' "$*"; }
log(){ xecho "$*"; }
warn(){ xecho "${YLW}WARN:${DEF} $*"; }
err(){ xecho "${RED}ERROR:${DEF} $*" >&2; }
die(){ err "$*"; exit "${2:-1}"; }
dbg(){ [[ ${DEBUG:-0} -eq 1 ]] && xecho "[DBG] $*" || :; }

# Package managers
pm_detect(){
  if has paru; then printf 'paru'; return; fi
  if has yay; then printf 'yay'; return; fi
  if has pacman; then printf 'pacman'; return; fi
  if has apt; then printf 'apt'; return; fi
  printf ''
}
PKG_MGR=${PKG_MGR:-$(pm_detect)}

# Tool detection with fallbacks
FD=${FD:-$(command -v fd || command -v fdfind || true)}
RG=${RG:-$(command -v rg || command -v grep || true)}
BAT=${BAT:-$(command -v bat || command -v cat || true)}

# Safe workspace
WORKDIR=$(mktemp -d)
cleanup(){
  set +e
  [[ -n ${LOCK_FD:-} ]] && exec {LOCK_FD}>&- || :
  [[ -n ${LOOP_DEV:-} && -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" || :
  [[ -n ${MNT_PT:-} ]] && mountpoint -q -- "${MNT_PT}" && sudo umount -R "${MNT_PT}" || :
  [[ -d ${WORKDIR:-} ]] && rm -rf "${WORKDIR}" || :
}
on_err(){ err "failed at line ${1:-?}"; }
trap 'cleanup' EXIT
trap 'on_err $LINENO' ERR
trap ':' INT TERM

# Config
declare -A cfg=([dry_run]=0 [debug]=0 [quiet]=0 [assume_yes]=0)
run(){ if (( cfg[dry_run] )); then log "[DRY] $*"; else "$@"; fi; }

# Parse args
parse_args(){
  while (($#)); do
    case "$1" in
      -q) cfg[quiet]=1;;
      -v) cfg[debug]=1; DEBUG=1;;
      -y) cfg[assume_yes]=1;;
      -o) OUT=${2:?}; shift;;
      --help|-h) usage; exit 0;;
      --version) printf '%s\n' "1.0.0"; exit 0;;
      --) shift; break;;
      -*) usage; die "invalid option: $1";;
      *) break;;
    esac
    shift
  done
  ARGS=("$@")
}

main(){
  parse_args "$@"
  (( cfg[quiet] )) && exec >/dev/null
  (( cfg[debug] )) && dbg "verbose on"

  # Your logic here

  log "done"
}

main "$@"
```

## Arch Build Environment

```bash
export CFLAGS="-march=native -mtune=native -O3 -pipe"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$(nproc)" NINJAFLAGS="-j$(nproc)"
export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat"
command -v ld.lld &>/dev/null && export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
```

## AUR Helper Flags

```bash
AUR_FLAGS=(--needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --batchinstall)
```

## Network Operations

- Use hardened curl: `curl -fsSL --proto '=https' --tlsv1.3`
- Prefer retries/backoff for flaky endpoints
- Avoid needless downloads
- Update README curl snippets when entrypoints change

## Device Operations (Pi & Imaging)

- Derive partition suffix: `[[ $dev == *@(nvme|mmcblk|loop)* ]] && p="${dev}p1" || p="${dev}1"`
- Wait for device nodes with retry loop
- Use `udevadm settle` when needed
- Always `umount -R` in cleanup
- Detach loop devices; ignore errors but log

## Detection Helpers

### Wayland
```bash
is_wayland(){ [[ ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ]]; }
```

### Distribution
```bash
is_arch(){ has pacman; }
is_debian(){ has apt; }
is_pi(){ [[ $(uname -m) =~ ^(arm|aarch64) ]]; }
```

## Data Processing Patterns

### Load filtered config/package lists
```bash
mapfile -t arr < <(grep -v '^\s*#' file.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
```

### Install from list
```bash
printf '%s\n' "${arr[@]}" | paru -Sq --noconfirm
```

## Testing Strategy

- **Unit:** `bats-core` for individual functions
- **Integration:** End-to-end scenarios on Arch/Debian
- **Static:** `shellcheck --severity=style`
- **Format:** `shfmt -i 2 -ci -sr`
- **Performance:** `hyperfine` for critical paths
- **Distro compat:** Test on Arch and Debian

## GitHub Workflows

- **`mega-linter.yml`** - Comprehensive linting
- **`shell.yml`** - ShellCheck validation
- **`img-opt.yml`** - Image optimization
- **`deps.yml`** - Dependency updates (Dependabot)
- **`aio.yml`** - All-in-one CI
- **`copilot-setup-steps.yml`** - Copilot configuration

## ShellCheck Configuration

Located in `.shellcheckrc`:
- Shell: bash
- External sources enabled
- Source path: SCRIPTDIR
- Disabled checks: SC1079, SC1078, SC1073, SC1072, SC1083, SC2086, SC1090, SC1091, SC2002, SC2016, SC2034, SC2154, SC2155, SC2236, SC2250, SC2312

## EditorConfig

- **Default indent:** 2 spaces
- **Line endings:** LF
- **Charset:** UTF-8
- **Max line length:** 120 (general), 100 (Rust/C++), 88 (Python), 80 (Markdown)
- **Shell scripts:** 2-space indent, bash variant
- **Trailing whitespace:** Trimmed (except Markdown)
- **Final newline:** Required

## Common Patterns

### Source lib/core.sh
```bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/../lib/core.sh" || exit 1
```

### Locking
```bash
lock(){
  local key=${1:?}
  exec {LOCK_FD}>"/run/lock/${key//[^[:alnum:]]/_}.lock" || die "lock fd"
  flock -n "$LOCK_FD" || die "lock taken: $key"
}
```

### Interactive selection with fzf
```bash
select_file(){
  local -n result=$1
  local pattern=${2:-'.*'}
  if [[ -n $FD ]]; then
    result=$("$FD" -H -t f "$pattern" | fzf --prompt="Select file: ")
  else
    result=$(find . -type f -name "*${pattern}*" | fzf --prompt="Select file: ")
  fi
}
```

## Repository-Specific Scripts

### Cachyos/Updates.sh
System update orchestrator for Arch/CachyOS systems. Updates packages, cleans cache, optimizes databases.

### Cachyos/clean.sh
Comprehensive system cleanup: package cache, orphans, logs, trash, build artifacts.

### Cachyos/Rank.sh
Mirror ranking and keyring updates for optimal package download speeds.

### Cachyos/Setup.sh
Automated system configuration: sysctl tuning, service setup, optimization.

### RaspberryPi/raspi-f2fs.sh
F2FS imaging orchestrator for Raspberry Pi. Handles loop devices, partitioning, formatting.

### RaspberryPi/Scripts/Setup.sh
Initial Raspberry Pi setup: package installation, configuration, service setup.

### RaspberryPi/Scripts/Kbuild.sh
Kernel building automation for Raspberry Pi with optimized flags.

## Design Principles

1. **Single Responsibility:** Functions do one thing well
2. **Loose Coupling:** Minimize dependencies between components
3. **Early Returns:** Exit fast on errors or edge cases
4. **Avoid Over-Abstraction:** Don't generalize prematurely
5. **Eliminate Duplication:** Reuse helpers from `lib/core.sh` and `Shell-book.md`
6. **Clear Intent:** Code should be self-documenting; comment only for "why" not "what"

## References

- **Bash Manual:** https://www.gnu.org/software/bash/manual/
- **Google Shell Style:** https://google.github.io/styleguide/shellguide.html
- **ShellCheck:** https://www.shellcheck.net/wiki/
- **Pure Bash Bible:** https://github.com/dylanaraps/pure-bash-bible
- **EditorConfig:** https://editorconfig.org/
- **CachyOS:** https://cachyos.org/
- **Arch Wiki:** https://wiki.archlinux.org/

## Token-Efficient Notation

- **Symbols:** → leads, ⇒ converts, ← rollback, ⇄ bidir, & and, | or, » then, ∴ therefore, ∵ because
- **Status:** ✅ done, ❌ fail, ⚠️ warn, 🔄 active, ⏳ pending, 🚨 critical
- **Domains:** ⚡ perf, 🔍 analysis, 🔧 cfg, 🛡️ sec, 📦 deploy, 🎨 UI, 🏗️ arch, 🗄️ DB, ⚙️ backend, 🧪 test
- **Abbrev:** cfg, impl, arch, req, deps, val, auth, qual, sec, err, opts

## Review Checklist

Before committing, verify:
- [ ] Starts with `#!/usr/bin/env bash`
- [ ] Has `set -Eeuo pipefail` and shopt flags
- [ ] Uses arrays/mapfile/`[[...]]` and parameter expansion
- [ ] Avoids parsing `ls`, using `eval`, backticks
- [ ] Logging helpers present
- [ ] Traps for cleanup and ERR with line numbers
- [ ] Privilege via `sudo`; package manager detection
- [ ] Arch/Debian paths handled
- [ ] Rust tools preferred with fallbacks
- [ ] Flags parsed via short options (`-q -v -y -o`)
- [ ] Supports `--help`/`--version`
- [ ] Linted (shfmt, shellcheck)
- [ ] Minimal external calls
- [ ] Parallelized safely
- [ ] Tests pass (if applicable)
- [ ] No trailing whitespace
- [ ] No hidden Unicode characters
