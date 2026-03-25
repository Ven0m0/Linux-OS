# GitHub Copilot Instructions

> Focused rules for inline completions and chat in the Linux-OS repository.
> Full canonical reference: [`AGENTS.md`](../AGENTS.md) (root of repo).

---

## Control Hierarchy

1. User commands override all rules.
2. Edit > Create — modify minimal lines, preserve existing style.
3. Subtraction > Addition — remove before adding.
4. Align with existing patterns in the file being edited.

---

## Target Systems

| Primary | Secondary | Tertiary |
|:--------|:----------|:---------|
| Arch / CachyOS / Wayland | Debian / Raspbian / Pi OS | Termux / EndeavourOS |

---

## Bash Standards

### Header (every script)

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C
```

### Idioms

| Rule | Good | Bad |
|:-----|:-----|:----|
| Tests | `[[ $x == y ]]` | `[ $x = y ]` |
| Loops | `while IFS= read -r l; do ...; done < <(cmd)` | `for x in $(cmd)` |
| Output | `printf '%s\n' "$var"` | `echo $var` |
| Strings | `${var##*/}` (basename), `${var,,}` (lower) | `$(basename "$var")`, `$(tr ...)` |
| Arrays | `mapfile -t arr < <(cmd)` | `arr=($(cmd))` |
| Functions | `name(){ local x; ... }` | `function name { ... }` |
| Namerefs | `local -n result=$1` | globals for output |
| **Never** | `eval`, backticks, parsing `ls`, unnecessary subshells | — |

### Quoting

Always quote variables. Exception: intentional glob/split, `$*` in printf format.

---

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

# Package manager detection
pm_detect(){
  has paru && printf 'paru' && return
  has yay  && printf 'yay'  && return
  has pacman && printf 'pacman' && return
  has apt  && printf 'apt'  && return
  printf ''
}
PKG_MGR=${PKG_MGR:-$(pm_detect)}

# Tool fallbacks
FD=${FD:-$(command -v fd || command -v fdfind || true)}
RG=${RG:-$(command -v rg || command -v grep || true)}
BAT=${BAT:-$(command -v bat || command -v cat || true)}

# Workspace & cleanup
WORKDIR=$(mktemp -d)
cleanup(){
  set +e
  [[ -n ${LOCK_FD:-} ]] && exec {LOCK_FD}>&- || :
  [[ -n ${LOOP_DEV:-} && -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" || :
  [[ -n ${MNT_PT:-} ]] && mountpoint -q -- "${MNT_PT}" && sudo umount -R "${MNT_PT}" || :
  [[ -d ${WORKDIR:-} ]] && rm -rf "${WORKDIR}" || :
}
trap 'cleanup' EXIT
trap 'err "failed at line $LINENO"' ERR
trap ':' INT TERM

# Config
declare -A cfg=([dry_run]=0 [debug]=0 [quiet]=0 [assume_yes]=0)
run(){ (( cfg[dry_run] )) && log "[DRY] $*" || "$@"; }

# Arg parser
parse_args(){
  while (($#)); do
    case "$1" in
      -q) cfg[quiet]=1 ;;
      -v) cfg[debug]=1; DEBUG=1 ;;
      -y) cfg[assume_yes]=1 ;;
      -n) cfg[dry_run]=1 ;;
      --help|-h) usage; exit 0 ;;
      --version) printf '1.0.0\n'; exit 0 ;;
      --) shift; break ;;
      -*) usage; die "invalid option: $1" ;;
      *) break ;;
    esac
    shift
  done
  ARGS=("$@")
}

main(){
  parse_args "$@"
  (( cfg[quiet] )) && exec >/dev/null
  (( cfg[debug] )) && dbg "verbose on"

  # logic here

  log "done"
}

main "$@"
```

---

## Tool Hierarchy (Fallbacks Required)

```
fd → fdfind → find
rg → grep -E  (grep -F for literals)
bat → cat
sd → sed -E
aria2c → curl → wget2 → wget
jaq → jq
rust-parallel → parallel → xargs -r -P$(nproc)
```

---

## Package Management

```bash
# Arch — prefer AUR helpers
paru -S --needed --noconfirm --removemake --cleanafter pkg

# Check before install
pacman -Q "$pkg" &>/dev/null || paru -S --noconfirm "$pkg"
flatpak list --app | grep -qF "$pkg" || flatpak install -y "$pkg"
cargo install --list | grep -qF "$pkg" || cargo install "$pkg"

# Debian
apt-get install -y --no-install-recommends pkg
```

---

## Security Patterns

```bash
# Command injection — use arrays, never eval
local -a cmd=(pacman -S -- "$pkg")
"${cmd[@]}"

# Path validation
validate_path(){
  local p=${1:?}
  [[ $p =~ ^[[:alnum:]/_.-]+$ ]] || die "invalid path: $p"
  [[ ! $p =~ \.\. ]]            || die "path traversal: $p"
}

# Package name validation
validate_pkg(){
  local pkg=${1:?}
  [[ $pkg =~ ^[a-z0-9@._+-]+$ ]] || die "invalid pkg: $pkg"
}

# Temp files — never predictable names
TMPFILE=$(mktemp) || die "mktemp failed"
chmod 600 "$TMPFILE"

# Atomic writes
printf '%s\n' "$content" > "${file}.tmp"
mv -f "${file}.tmp" "$file"
```

---

## Error Handling

```bash
# Full cleanup trap (copy into every script)
cleanup(){
  set +e
  local rc=$?
  [[ -n ${LOCK_FD:-} ]] && exec {LOCK_FD}>&- 2>/dev/null || :
  [[ -n ${LOOP_DEV:-} && -b ${LOOP_DEV} ]] && losetup -d "$LOOP_DEV" 2>/dev/null || :
  [[ -n ${MNT_PT:-} ]] && mountpoint -q "$MNT_PT" && sudo umount -R "$MNT_PT" || :
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR" || :
  return "$rc"
}
trap cleanup EXIT
trap 'err "interrupted"; exit 130' INT TERM
trap 'err "failed at line $LINENO"' ERR

# Retry with exponential backoff
retry(){
  local -i max=${1:?} delay=${2:-2} attempt=0
  shift 2
  until "$@"; do
    (( ++attempt >= max )) && die "failed after $max attempts: $*"
    warn "attempt $attempt/$max failed, retrying in ${delay}s..."
    sleep "$delay"; (( delay *= 2 ))
  done
}
# Usage: retry 4 2 git push -u origin main

# Locking
lock(){
  local key=${1:?}
  local lockfile="/run/lock/${key//[^[:alnum:]]/_}.lock"
  exec {LOCK_FD}>"$lockfile" || die "lock fd failed: $key"
  flock -n "$LOCK_FD"        || die "lock taken: $key"
}
```

---

## Performance Rules

- Minimize forks/subshells: use `${var##*/}` not `$(basename)`, `${var,,}` not `$(tr ...)`.
- Batch I/O: `mapfile -t`, single `printf '%s\n' "${arr[@]}" | xargs -r -P"$(nproc)"`.
- Cache `has` checks outside loops.
- Anchor regexes: `^pattern$`. Literal search: `grep -F`, `rg -F`.
- Measure with `hyperfine` before optimizing.

---

## Quality Gates

Run before every commit:

```bash
./lint-format.sh          # shfmt + shellcheck (auto-fixes)
./lint-format.sh --check  # check-only (CI mode)
```

Manual:

```bash
shfmt -i 2 -ci -sr -w script.sh
shellcheck --severity=style script.sh
bash -n script.sh
```

Excludes: `Cachyos/Scripts/WIP/`, `.github/agents/`

---

## Protected Files

**Do NOT modify without explicit user request:**

`pacman.conf`, `makepkg.conf`, `/etc/sysctl.d/*`, `.zshrc`, `.gitconfig`

**Safe to edit:** shell scripts, `.config/`, docs, workflows.

---

## Detection Helpers

```bash
is_wayland(){ [[ ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ]]; }
is_arch(){    has pacman; }
is_debian(){  has apt; }
is_pi(){      [[ $(uname -m) =~ ^(arm|aarch64) ]]; }
```

---

## Exit Codes

| Code | Meaning |
|:-----|:--------|
| 0 | Success |
| 1 | General error |
| 2 | Misuse of shell builtins |
| 126 | Cannot execute |
| 127 | Not found |
| 130 | Ctrl+C |
