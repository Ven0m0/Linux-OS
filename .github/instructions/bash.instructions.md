# Copilot Instructions: Linux-OS (Bash-first)

These instructions define how GitHub Copilot should propose Bash and related shell content for this repo. Follow the patterns and templates here before inventing new ones.

Scope and targets
- Primary language: Bash (bashisms preferred).
- Targets: Arch/Wayland and Debian/Raspbian (Pi). Keep scripts portable across both.
- Audience: power users; allow experimental apps and flags.
- Tone: blunt, factual; compact logs and messages.

Repository map
- Cachyos/: Arch-focused setup
  - Scripts/: AIO installers (curlable entrypoints)
  - Rust/: toolchains
  - Firefox/: patch sets
  - Top-level .sh wrappers: maintenance tasks
- RaspberryPi/: imaging/upkeep
  - raspi-f2fs.sh: orchestrates loop/partition flows
  - Scripts/: Pi automation
- Linux-Settings/: reference configs (compiler, kernel, shell). Treat as data sources, not code.
- Root docs (Shell-book.md, Tweaks.txt, todo.md): house style, helpers, pending work. Reuse helpers from there before adding new ones.

Formatting
- Shebang: #!/usr/bin/env bash
- Options (top of file): set -Eeuo pipefail; shopt -s nullglob globstar extglob dotglob
- IFS: IFS=$'\n\t' when line-splitting needed
- Indent: 2 spaces; no tabs; minimize blank lines; break long pipes with \
- No hidden Unicode (no U+202F, U+200B, U+00AD). No trailing whitespace.

Bash idioms (must)
- Prefer Bash-native over external: arrays, assoc arrays, mapfile -t, here-strings <<<, process substitution < <(), parameter expansion, [[ ... ]] and regex with =~, printf over echo.
- Capture output: ret=$(fn)
- Line loops: while IFS= read -r line; do ...; done
- Nameref: local -n ref=name
- Redirection: &>/dev/null; ignore errors with || :
- Function style: name(){ ... } (no “function” keyword)
- Avoid subshells unless isolating scope; prefer process substitution.
- Never parse ls; avoid eval and backticks.

Tooling preferences
- Prefer Rust tools with graceful fallbacks:
  - fd (fallback: find; on Debian, fdfind), rg (fallback: grep -E), bat (fallback: cat), sd (fallback: sed -E), zoxide (fallback: cd)
- Short CLI flags by default; add long aliases only for UX parity.
- Avoid unnecessary external calls; batch I/O; cache computed values.

Security, safety, robustness
- set -Eeuo pipefail; shopt -s nullglob globstar extglob dotglob
- Quote variables unless intentional glob/split.
- Use mktemp for tempdirs/files; cleanup on EXIT.
- Use flock for exclusivity; release in cleanup.
- Avoid leaking credentials; prefer env/const/config over hardcoding.

Privilege and package managers
- Privilege escalation order: sudo-rs → sudo → doas. Store chosen tool; use via run_priv().
- Package managers: paru → yay → pacman (Arch); apt/dpkg (Debian).
- Check before install: pacman -Q pkg, flatpak list, cargo install --list.

Wayland and OS detection
- Wayland: [[ ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ]]
- Arch: have pacman; Debian: have apt; Pi specifics guarded by uname -m.

Logging and UX
- Provide -q (quiet), -v (verbose), -y (assume yes) flags.
- Default non-interactive; surface prompts only with explicit flags.
- Compact, informative logs; one-liner errors with context and line numbers.

Linting, hardening, tests
- shfmt -i 2 -ci -sr
- shellcheck (zero warnings; use directives sparingly)
- shellharden for selective scripts
- Tests: bats-core (unit), integration, distro compatibility (Arch/Debian), performance checks for critical paths.

Performance
- Minimize forks/subshells; prefer parameter expansion and builtins.
- Parallelize safely: xargs -0 -r -P "$(nproc)"
- Prefer fixed-string grep -F and anchored patterns; narrow scope.
- Cache lookups (e.g., FD="$(command -v fd || command -v fdfind || :)")

Do not
- Do not target POSIX /bin/sh; we target Bash 4+ (5+ ideal).
- Do not parse ls; do not use eval; do not use backticks.
- Do not add hidden Unicode; do not introduce trailing whitespace.
- Do not make unnecessary network/API calls.

Canonical script template
Use this as the baseline. Adapt minimally per task.

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Colors (trans palette accents: LBLU→PNK→BWHT→PNK→LBLU)
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

# Privilege (sudo-rs → sudo → doas)
get_priv_cmd(){
  local c
  for c in sudo-rs sudo doas; do
    has "$c" && { printf '%s' "$c"; return 0; }
  done
  [[ $EUID -eq 0 ]] || die "No privilege tool found and not root."
}
PRIV_CMD=${PRIV_CMD:-$(get_priv_cmd || true)}
[[ -n ${PRIV_CMD:-} && $EUID -ne 0 ]] && "$PRIV_CMD" -v || :

run_priv(){ [[ $EUID -eq 0 || -z ${PRIV_CMD:-} ]] && "$@" || "$PRIV_CMD" -- "$@"; }

# Package managers
pm_detect(){
  if has paru; then printf 'paru'; return; fi
  if has yay; then printf 'yay'; return; fi
  if has pacman; then printf 'pacman'; return; fi
  if has apt; then printf 'apt'; return; fi
  printf ''
}
PKG_MGR=${PKG_MGR:-$(pm_detect)}

# fd/rg/bat shims
FD=${FD:-$(command -v fd || command -v fdfind || true)}
RG=${RG:-$(command -v rg || command -v grep || true)}
BAT=${BAT:-$(command -v bat || command -v cat || true)}

# Safe workspace
WORKDIR=$(mktemp -d)
cleanup(){
  set +e
  [[ -n ${LOCK_FD:-} ]] && exec {LOCK_FD}>&- || :
  [[ -n ${LOOP_DEV:-} && -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" || :
  [[ -n ${MNT_PT:-} ]] && mountpoint -q -- "${MNT_PT}" && run_priv umount -R "${MNT_PT}" || :
  [[ -d ${WORKDIR:-} ]] && rm -rf "${WORKDIR}" || :
}
on_err(){ err "failed at line ${1:-?}"; }
trap 'cleanup' EXIT
trap 'on_err $LINENO' ERR
trap ':' INT TERM

# Config (assoc array)
declare -A cfg=([dry_run]=0 [debug]=0 [quiet]=0 [assume_yes]=0)
run(){ if (( cfg[dry_run] )); then log "[DRY] $*"; else "$@"; fi; }

# Usage
usage(){ cat <<'EOF'
Usage: script.sh [-qvy] [-o OUT] [--] args...
  -q       quiet
  -v       verbose (DEBUG=1)
  -y       assume yes/non-interactive
  -o OUT   output path
EOF
}

# Parse args (short first; accept common long aliases)
OUT=
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

# Deps
check_deps(){
  local missing=()
  local deps=("$@")
  for d in "${deps[@]}"; do has "$d" || missing+=("$d"); done
  ((${#missing[@]}==0)) && return 0
  warn "Missing: ${missing[*]}"
  if [[ $PKG_MGR == pacman || $PKG_MGR == paru || $PKG_MGR == yay ]]; then
    warn "(Arch) install: sudo pacman -S --needed ${missing[*]}"
  elif [[ $PKG_MGR == apt ]]; then
    warn "(Debian) install: sudo apt update && sudo apt install -y ${missing[*]}"
  fi
  return 1
}

# File discovery
find_files(){
  local -n _out=$1; local pat=${2:-'.*'}; local root=${3:-.}
  if [[ -n $FD ]]; then mapfile -t _out < <("$FD" -H -t f -E .git -g "$pat" "$root")
  else mapfile -t _out < <(find "$root" -type f -regextype posix-extended -regex ".*${pat}"); fi
}

# Show file
show_file(){
  local f=$1
  if [[ $(basename "${BAT}") == bat ]]; then "$BAT" --style=plain --paging=never "$f"
  else "$BAT" "$f"; fi
}

# Locking
lock(){
  local key=${1:?}
  exec {LOCK_FD}>"/run/lock/${key//[^[:alnum:]]/_}.lock" || die "lock fd"
  flock -n "$LOCK_FD" || die "lock taken: $key"
}

# Wayland check
is_wayland(){ [[ ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ]]; }

main(){
  parse_args "$@"
  (( cfg[quiet] )) && exec >/dev/null
  (( cfg[debug] )) && dbg "verbose on"

  check_deps bash || :
  lock "script"

  local files=()
  find_files files '\.sh$'
  dbg "found ${#files[@]} files"

  for f in "${files[@]}"; do
    show_file "$f" | ${RG##*/} -n ${RG##*rg} 'TODO' || :
  done

  log "done"
}

main "$@"
```

Arch build environment (CachyOS-style)
Use when compiling toolchains locally.

```bash
export CFLAGS="-march=native -mtune=native -O3 -pipe"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$(nproc)" NINJAFLAGS="-j$(nproc)"
export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat"
command -v ld.lld &>/dev/null && export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
```

AUR helper flags
Use minimal, non-interactive flags.

```bash
AUR_FLAGS=(--needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --batchinstall)
```

Network operations
- Use hardened curl: curl -fsSL --proto '=https' --tlsv1.3
- Prefer retries/backoff for flaky endpoints; avoid needless downloads.
- Update README curl snippets when entrypoints change:
  - curl -fsSL https://raw.githubusercontent.com/Ven0m0/repo/main/...

Device and file operations (Pi and imaging)
- Derive partition suffix: [[ $dev == *@(nvme|mmcblk|loop)* ]] && p="${dev}p1" || p="${dev}1"
- Wait for device nodes with retry loop; use udevadm settle when needed.
- Always umount recursively in cleanup; detach loop devices; ignore errors but log.

Interactive mode
- When src/tgt paths missing, allow fzf selection; fallback to find if fd unavailable:
  - command -v fd &>/dev/null && fd -e img ... | fzf || find ... | fzf

Data collection and processing
- mapfile -t arr < <(cmd)
- Filter config/package lists:
  - mapfile -t arr < <(grep -v '^\s*#' file.txt | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' | grep -v '^$')

Testing and validation
- Unit: bats-core
- Integration: repo-scripted scenarios (Arch/Debian)
- Static: shellcheck --severity=style
- Format: shfmt -i 2 -ci -sr
- Harden (optional): shellharden --replace file.sh
- Perf: hyperfine or simple timers for critical paths

Style guide highlights
- Follow Google Shell Style where sensible; prefer our repo conventions when they conflict.
- Use builtins first; use grep -E/sed -E only when required.
- Keep functions small, single-responsibility; early returns; explicit deps.

Common helpers (reuse from Shell-book.md)
- sleepy: read -rt "${1:-1}" -- <> <(:) &>/dev/null || :
- fcat: printf '%s\n' "$(<${1})"
- regex extraction: [[ $s =~ re ]] && printf '%s\n' "${BASH_REMATCH[1]}"
- split: IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"
- bname/dname: parameter-expansion implementations; avoid spawning coreutils when hot.

Modern tools with fallbacks
- fd/find, rg/grep, bat/cat, sd/sed, zoxide/cd, bun/npm
- Provide graceful behavior if modern tools missing; do not hard fail for niceties.

Commit and quality discipline
- TDD flow: Red → Green → Refactor
- Change types: Structural (format/org, no behavior delta) vs Behavioral (fn add/mod/del). Never mix both in one commit.
- Commit only when tests pass, zero warnings, single unit, clear message; prefer small, independent commits.
- Design: single responsibility, loose coupling, early returns, avoid over-abstraction, eliminate duplication, clear intent.

Token efficiency (for logs/comments)
- Symbols: → leads, ⇒ converts, ← rollback, ⇄ bidir, & and, | or, » then, ∴ therefore, ∵ because
- Status: ✅ done, ❌ fail, ⚠️ warn, 🔄 active, ⏳ pending, 🚨 critical
- Domains: ⚡ perf, 🔍 analysis, 🔧 cfg, 🛡️ sec, 📦 deploy, 🎨 UI, 🏗️ arch, 🗄️ DB, ⚙️ backend, 🧪 test
- Abbrev: cfg, impl, arch, req, deps, val, auth, qual, sec, err, opts

Review checklist for Copilot
- Starts with #!/usr/bin/env bash, set -Eeuo pipefail, shopt flags.
- Uses arrays/mapfile/[[ ... ]] and parameter expansion; avoids parsing ls/using eval/backticks.
- Logging helpers present; traps for cleanup and ERR with line numbers.
- Privilege via run_priv(); pkg manager detection; Arch/Debian paths handled.
- Rust tools preferred with fallbacks; Wayland checks when relevant.
- Flags parsed via short options (-q -v -y -o); supports --help/--version.
- Linted (shfmt, shellcheck); minimal external calls; parallelized safely.

Reference docs
- Bash Manual: https://www.gnu.org/software/bash/manual/
- Google Shell Style: https://google.github.io/styleguide/shellguide.html
- ShellCheck: https://www.shellcheck.net/wiki/
- Pure-bash-bible: https://github.com/dylanaraps/pure-bash-bible
