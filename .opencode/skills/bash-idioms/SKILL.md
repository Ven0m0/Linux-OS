---
name: bash-idioms
description: Linux-OS repository bash coding standards — forbidden patterns, required idioms, performance rules, and the canonical script template. Use when writing or reviewing any .sh file in this repo.
---

## Required Header

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C
```

## Forbidden Patterns

| Pattern | Replacement |
|---------|-------------|
| `eval` | Never — use arrays |
| Backticks `` `cmd` `` | `$(cmd)` |
| `for x in $(ls)` | `for x in */` or `mapfile` |
| `echo` for output | `printf '%s\n'` |
| `function foo()` | `foo(){ ... }` |
| `$(basename "$f")` | `${f##*/}` |
| `$(dirname "$f")` | `${f%/*}` |
| `$(cat file)` | `$(<file)` |
| `cat f | cmd` | `cmd < f` |
| `cat f | grep` | `grep '' f` |

## Required Idioms

```bash
# Command existence
has(){ command -v "$1" &>/dev/null; }

# Logging hierarchy
log(){ printf '%b\n' "$*"; }
warn(){ printf '%b\n' "${YLW}WARN:${DEF} $*"; }
err(){ printf '%b\n' "${RED}ERROR:${DEF} $*" >&2; }
die(){ err "$*"; exit "${2:-1}"; }
dbg(){ [[ ${DEBUG:-0} -eq 1 ]] && printf '[DBG] %s\n' "$*" || :; }

# Output params via nameref (no subshell)
get_name(){ local -n _out=$1; _out="${2##*/}"; }

# Array loading from file (strip comments + blank lines)
mapfile -t arr < <(grep -Ev '^\s*(#|$)' file.txt)

# Parallel execution
printf '%s\n' "${items[@]}" | xargs -r -P"$(nproc)" -I{} process {}
```

## Trap Pattern

```bash
cleanup(){
  set +e
  [[ -n ${LOCK_FD:-} ]] && exec {LOCK_FD}>&- 2>/dev/null || :
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR" || :
}
trap 'cleanup' EXIT
trap 'err "failed at line $LINENO"' ERR
trap ':' INT TERM
```

## Color Palette (trans flag)

```bash
LBLU=$'\e[38;5;117m'  # Light blue
PNK=$'\e[38;5;218m'   # Pink
BWHT=$'\e[97m'        # Bright white
DEF=$'\e[0m'          # Reset
BLD=$'\e[1m'          # Bold
```

## Performance: Cost Table

| ❌ Expensive | ✅ Cheap |
|------------|--------|
| `$(command)` subshell | `${var//pat/rep}` |
| `tr` | `${var,,}` / `${var^^}` |
| `basename` | `${f##*/}` |
| `dirname` | `${f%/*}` |
| `cat file` | `$(<file)` |

## Quoting Rules

- Always quote variables: `"$var"`, `"${arr[@]}"`
- Exception: intentional word-split/glob, and `$*` in printf format
- Use `--` before user-supplied args to commands: `rm -- "$file"`

## Input Validation

```bash
validate_path(){
  [[ $1 =~ ^[[:alnum:]/_.-]+$ ]] || die "invalid path: $1"
  [[ ! $1 =~ \.\. ]] || die "path traversal: $1"
}
validate_pkg(){
  [[ $1 =~ ^[a-z0-9@._+-]+$ ]] || die "invalid pkg: $1"
}
```
