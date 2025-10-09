# Copilot Instructions: Bash Single-File Baseline

Purpose
- Generate compact, production-grade, single-file Bash tools.
- Optimize for Arch (Wayland) and Debian (Raspberry Pi). Secondary: Termux.
- Favor in-memory ops, minimal external processes, Rust tools when available.

Single-File First
- No external library sourcing by default. Keep helpers inline.
- Short usage output, fast startup (<100ms).
- Add completions/docs/tests only when the script stabilizes.

Style and Defaults
- Shebang: `#!/usr/bin/env bash` (Termux when explicitly targeting it: `#!/data/data/com.termux/files/usr/bin/env bash`)
- Strict early:
  ```bash
  set -euo pipefail
  IFS=$'\n\t'
  shopt -s nullglob globstar
  export LC_ALL=C LANG=C LANGUAGE=C
  ```
- 2-space indent. Short CLI args via `getopts`.
- Prefer:
  - Arrays and associative arrays
  - Here-strings: `cmd <<<"$var"`
  - `while IFS= read -r` for input
  - `[[ ... ]]` for tests
  - nameref for in/out params: `fn(){ local -n out=$1; ...; out=value; }`
  - `ret=$(fn ...)` to capture outputs
  - Parameter expansion and `mapfile -t` over external tools
- Regex: use `grep -E`/`expr` for matching. Avoid `[[ str =~ re ]]` portability footguns.
- Silence non-critical failures: `cmd >/dev/null 2>&1 || true`

Dependencies
- Prefer Rust tools when present: `fd`, `rg`, `bat`, `sd`, `zoxide`.
- Fallbacks must work: `find`, `grep -R`, `sed`, `awk`, `less`.
- Provide install hints on error for Arch (`pacman`), Debian (`apt`), Termux (`pkg`).
- Gate GNU-only flags behind checks.

Performance
- Avoid UUoC and pointless `awk`/`sed` when parameter expansion suffices.
- Prefer builtins, globbing, arithmetic.
- Use `fd`/`rg` if available; fallback to `find`/`grep -R`.
- Parallelize safe workloads: `xargs -0 -n1 -P"$(nproc 2>/dev/null || echo 1)"`.
- Avoid subshells where state is needed; use process substitution.

Filesystem and Safety
- Quote variables; never parse `ls`; avoid untrusted `eval`.
- Temp files: `mktemp -p "${TMPDIR:-/tmp}"`.
- Atomic writes: write temp then `mv`.
- Backups: `file.bak.$(date +%Y%m%d-%H%M%S)` before destructive ops.

Concurrency and Signals
- Trap `INT`/`TERM`. Clean up and exit with meaningful codes.
- `-j` controls concurrency. Default to `nproc` or 1.

Configuration
- Prefer flags and env overrides (`FOO=1 script -o out`).
- Optional `--print-config` (JSON when `jq` present) for debugging.

Privilege Escalation (optional)
- Resolve once: `sudo-rs` → `sudo` → `doas`. Validate and cache.
- Respect `$EUID`; refresh sudo timestamp when used.

Cross-Platform Targets
- Detect with `/etc/os-release` when needed; gate features per platform.
- Termux support is opt-in; avoid hardcoded paths unless explicitly targeting it.

Testing and CI
- Lint: `shellcheck`; Format: `shfmt -i 2 -ci -sr`.
- Tests: `bats-core` for critical paths.
- Keep CI fast (<2 minutes), matrix at least `ubuntu-latest`; add Arch via container when necessary.

Acceptance Criteria
- Follows style, safety, and performance rules above.
- Short help/usage, examples for key ops.
- Graceful dependency handling with distro hints.
- Fast by default; parallelizable when safe.
- Deterministic and offline-capable when possible.

Minimal Single-File Boilerplate (no logging)
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'; shopt -s nullglob globstar
export LC_ALL=C LANG=C LANGUAGE=C

SELF="${BASH_SOURCE[0]}"; SCRIPT_DIR="${SELF%/*}"
readonly SELF SCRIPT_DIR
cd -P -- "$SCRIPT_DIR" >/dev/null 2>&1 || true
PATH="$SCRIPT_DIR:$PATH"

# ---- deps ----
has(){ command -v -- "$1" >/dev/null 2>&1; }
_hint_arch(){ printf 'pacman -S --needed %s\n' "$*"; }
_hint_deb(){ printf 'sudo apt-get install -y %s\n' "$*"; }
_hint_termux(){ printf 'pkg install %s\n' "$*"; }
require_deps(){ local miss=(); for d in "$@"; do has "$d" || miss+=("$d"); done
  ((${#miss[@]}==0)) && return 0
  printf 'missing deps: %s\n' "${miss[*]}" >&2
  printf 'Arch:   %s' "$(_hint_arch "${miss[*]}")" >&2
  printf 'Debian: %s' "$(_hint_deb "${miss[*]}")" >&2
  printf 'Termux: %s' "$(_hint_termux "${miss[*]}")" >&2
  exit 127
}

# ---- helpers ----
die(){ printf '%s\n' "$*" >&2; exit 1; }
sleepy(){ read -rt "${1:-1}" -- <> <(:) >/dev/null 2>&1 || :; }  # fast sleep
fcat(){ printf '%s\n' "$(<"$1")"; }  # faster than cat for small files
bname(){ local t=${1%${1##*[!/}]}; t=${t##*/}; [[ $2 && $t == *"$2" ]] && t=${t%$2}; printf '%s\n' "${t:-/}"; }
dname(){ local p=${1:-.}; [[ $p != *[!/]* ]] && { printf '/\n'; return; }; p=${p%${p##*[!/]}}; [[ $p != */* ]] && { printf '.\n'; return; }; p=${p%/*}; p=${p%${p##*[!/]}}; printf '%s\n' "${p:-/}"; }

# Prefer expr/grep over [[ =~ ]] for portability
match(){ # match "string" "regex" -> prints first group via grep -E
  printf '%s\n' "$1" | grep -E -o "$2" >/dev/null 2>&1 || return 1
}

# ---- args ----
QUIET=0 VERBOSE=0 DRYRUN=0 ASSUME_YES=0
JOBS="${JOBS:-0}" OUT=""

usage(){
  cat <<EOF
Usage: $(basename "$SELF") [-h] [-q] [-v] [-n] [-y] [-j n] [-o path]
  -h  Help
  -q  Quiet (redirect stdout to /dev/null)
  -v  Verbose (set DEBUG=1 for extra prints)
  -n  Dry-run
  -y  Assume yes
  -j  Jobs (default: nproc or 1)
  -o  Output path
EOF
}

parse_args(){
  local opt
  while getopts ":hqvnyj:o:" opt; do
    case "$opt" in
      h) usage; exit 0;;
      q) QUIET=1;;
      v) VERBOSE=1; DEBUG=1;;
      n) DRYRUN=1;;
      y) ASSUME_YES=1;;
      j) JOBS="$OPTARG";;
      o) OUT="$OPTARG";;
      \?|:) usage; exit 64;;
    esac
  done
  shift $((OPTIND-1))
  if [[ -z "$JOBS" || "$JOBS" == 0 ]]; then
    JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)"
  fi
}

confirm(){
  local msg=${1:-Proceed?} ans
  (( ASSUME_YES == 1 )) && return 0
  printf '%s [y/N]: ' "$msg" >&2
  IFS= read -r ans || true
  [[ "$ans" == [Yy]* ]]
}

# ---- safety ----
cleanup(){ :; }
trap 'rc=$?; trap - EXIT; cleanup; exit "$rc"' EXIT
trap 'trap - INT; exit 130' INT
trap 'trap - TERM; exit 143' TERM

# ---- main ----
main(){
  parse_args "$@"
  (( QUIET == 1 )) && exec 1>/dev/null
  require_deps bash

  # Example: enumerate files via fd/find, parallel-safe scan
  local -a files=()
  if has fd; then mapfile -t files < <(fd -t f .)
  else mapfile -t files < <(find . -type f -print)
  fi

  printf '%s\0' "${files[@]}" | xargs -0 -n1 -P"$JOBS" bash -c '
    f=$1
    if command -v rg >/dev/null 2>&1; then rg -n "TODO" "$f" >/dev/null 2>&1 || true
    else grep -Rns "TODO" "$f" >/dev/null 2>&1 || true
    fi
  ' _
}

main "$@"
```

Notes aligned with your Shell-book
- Keep strict mode, `IFS`, and locale set early for deterministic behavior.
- Inline helpers like `has`, `sleepy`, `fcat`, `bname`, `dname` are allowed when they tighten hot paths.
- Privilege tool resolution (`sudo-rs` → `sudo` → `doas`) is optional; add only when the script needs escalation.
- Prefer `grep -E`/`expr` for regex; avoid `[[ =~ ]]` if portability matters.
- Use arrays, here-strings, and `while IFS= read -r` throughout.

When to extend
- Add `--print-config` (JSON via `jq` fallback to plain text) only for config-heavy tools.
- Add completions and `bats` tests once the interface is stable.
- Gate non-portable speedups and experimental features behind `--experimental` or `EXPERIMENTAL=1`.