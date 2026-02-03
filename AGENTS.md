# AI Agents Operating Manual

> Unified guidelines for AI assistants working with the Linux-OS repository.
> This file is the canonical source - @CLAUDE.md and @GEMINI.md are symlinks.

---

## Prime Directives

1. **User Primacy:** User commands override all rules.
2. **Factual Verification:** Use tools for versions/APIs. Never guess.
3. **Surgical Modification:** Edit > Create. Minimal line changes. Preserve existing style/logic.
4. **Debt-First:** Remove clutter/deps before adding. Subtraction > Addition.
5. **Autonomous Execution:** Act immediately. Minimize confirmations unless destructive.

---

## Repository Overview

**Linux-OS** is a collection of production-grade shell scripts for managing Linux distributions, primarily targeting Arch/CachyOS and Debian/Raspberry Pi systems.

### Target Systems

| **Primary** | **Secondary** | **Tertiary** |
|:------------|:--------------|:-------------|
| Arch Linux  | Debian        | Termux       |
| CachyOS     | Raspbian      | EndeavourOS  |
| Wayland     | Raspberry Pi OS | Gentoo     |
|             |               | Nobara, SteamOS, Bazzite |

### Repository Structure

```text
/
├── @Cachyos/                  # Arch/CachyOS-focused scripts
│   ├── Scripts/               # AIO installers (curlable entrypoints)
│   │   ├── bench.sh           # System benchmarking
│   │   └── Android/           # Termux optimizers
│   ├── up.sh                  # Comprehensive update orchestrator
│   ├── clean.sh               # System cleanup & privacy hardening
│   ├── setup.sh               # Automated system configuration
│   ├── Rank.sh                # Mirror ranking & keyring updates
│   ├── debloat.sh             # System debloating
│   └── rustbuild.sh           # Rust compilation helpers
├── @RaspberryPi/              # Raspberry Pi specific scripts
│   ├── Scripts/               # Pi automation tooling
│   │   ├── setup.sh           # Initial Pi setup & optimization
│   │   ├── Kbuild.sh          # Kernel building automation
│   │   ├── apkg.sh            # TUI package manager (fzf/skim)
│   │   └── podman-docker.sh   # Container setup
│   ├── raspi-f2fs.sh          # F2FS imaging orchestrator
│   ├── update.sh              # Pi update script
│   ├── PiClean.sh             # Pi cleanup automation
│   └── dots/                  # Dotfiles and configs
├── @.github/                  # GitHub configuration
│   ├── workflows/             # CI/CD pipelines (10 active)
│   ├── agents/                # AI agent personas (7 specialized)
│   ├── instructions/          # Guidance documents (12 files)
│   └── prompts/               # Task-specific prompts (6 files)
├── @Shell-book.md             # Bash patterns & helpers
├── @USEFUL.MD                 # Curated resources & snippets
├── @DIETPI_F2FS_GUIDE.md      # F2FS imaging guide
├── @.shellcheckrc             # ShellCheck configuration
└── @.editorconfig             # Code formatting rules
```

---

## Communication Style

- **Tone:** Blunt, factual, precise, concise. Technical English.
- **Format:** 2-space indent. No filler. Strip U+202F/U+200B/U+00AD.
- **Output:** Result-first (`Result ∴ Cause`). Group by domain. Lists ≤7 items.
- **Abbrev:** cfg, impl, deps, val, auth, opt, arch, req, qual, sec, err, opts, Δ.

### Notation & Symbols

- **Flow:** → leads, ⇒ converts, ← rollback, ⇄ bidir, » then, & and, | or
- **Logic:** ∴ therefore, ∵ because
- **Status:** ✅ done, ❌ fail, ⚠️ warn, 🔄 active, ⏳ pending, 🚨 critical
- **Domains:** ⚡ perf, 🔍 analysis, 🔧 cfg, 🛡️ sec, 📦 deploy, 🎨 UI, 🏗️ arch, 🗄️ DB, ⚙️ backend, 🧪 test

---

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

Always quote variables unless intentional glob/split. Exception: `$*` in printf format strings.

### Packages

- **Install:** `paru`→`yay`→`pacman` (Arch); `apt-get` (Debian); prefer AUR helpers for -S operations
- **Check before install:** `pacman -Q "$pkg" 2>/dev/null`, `flatpak list --app | grep -qF "$pkg"`, `cargo install --list | grep -qF "$pkg"`
- **AUR flags:** `--needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --batchinstall`

---

## Tool Hierarchy (Fallbacks Required)

| Task | Primary | Fallback Chain |
|:-----|:--------|:---------------|
| Find | `fd` | `fdfind`→`find` |
| Grep | `rg` | `grep -E` (prefer `-F` for literals) |
| View | `bat` | `cat` |
| Edit | `sd` | `sed -E` |
| Nav | `zoxide` | `cd` |
| Web | `aria2c` | `curl`→`wget2`→`wget` |
| JSON | `jaq` | `jq` |
| Parallel | `rust-parallel` | `parallel`→`xargs -r -P$(nproc)` |

---

## Script Architecture

Scripts are **standalone** with inlined helper functions (no shared lib/). See @Shell-book.md for complete patterns.

### Core Helper Functions

- **has()** - Check if command exists
- **xecho()** - Echo with formatting
- **log()/msg()/warn()/err()/die()** - Logging hierarchy
- **dbg()** - Debug logging (enabled by `DEBUG=1`)
- **confirm()** - User confirmation prompt
- **pm_detect()** - Package manager detection

### Color Palette (Trans Flag)

```bash
LBLU=$'\e[38;5;117m'  # Light blue
PNK=$'\e[38;5;218m'   # Pink
BWHT=$'\e[97m'        # Bright white
DEF=$'\e[0m'          # Reset
BLD=$'\e[1m'          # Bold
```

---

## Performance

**Measure first. Optimize hot paths.** Use `hyperfine` for benchmarking.

### Bash Optimization

```bash
# ✅ GOOD: Batch operations, single fork
mapfile -t files < <(fd -t f -e sh)
printf '%s\n' "${files[@]}" | xargs -r shellcheck

# ❌ BAD: Loop with multiple forks
for f in $(find . -name '*.sh'); do shellcheck "$f"; done

# ✅ GOOD: Builtin pattern matching
[[ $file == *.sh ]] && process "$file"

# ❌ BAD: External command
[[ $(basename "$file") =~ \.sh$ ]] && process "$file"

# ✅ GOOD: Builtin string ops
name=${file##*/}      # basename
dir=${file%/*}        # dirname
base=${file%.sh}      # remove extension

# ❌ BAD: Subshells
name=$(basename "$file")
dir=$(dirname "$file")
```

### I/O Optimization

```bash
# ✅ GOOD: Single pass with mapfile
mapfile -t lines < file.txt
for line in "${lines[@]}"; do process "$line"; done

# ❌ BAD: Multiple reads
while IFS= read -r line; do
  other_data=$(cat other_file)  # NEVER read in loop
done < file.txt

# ✅ GOOD: Redirect once
{
  log "starting"
  process_data
  log "done"
} >> logfile

# ❌ BAD: Multiple redirects
log "starting" >> logfile
process_data >> logfile
log "done" >> logfile
```

### Parallel Processing

```bash
# ✅ GOOD: Parallel with xargs
printf '%s\n' "${files[@]}" | xargs -r -P"$(nproc)" -I{} process {}

# ✅ BETTER: rust-parallel (if available)
printf '%s\n' "${files[@]}" | rust-parallel -j"$(nproc)" process

# Pattern: Process large lists in parallel
process_packages(){
  local -a pkgs=("$@")
  if has rust-parallel; then
    printf '%s\n' "${pkgs[@]}" | rust-parallel -j"$(nproc)" pacman -Q
  else
    printf '%s\n' "${pkgs[@]}" | xargs -r -P"$(nproc)" -n1 pacman -Q
  fi
}
```

---

## Protected Files

**Do NOT modify unless explicitly requested:**

- `pacman.conf`, `makepkg.conf`, `/etc/sysctl.d/`, `.zshrc`, `.gitconfig`

**Safe zones:** Shell scripts, `.config/`, docs, workflows.

---

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

---

## File Operations

- **Edit over create:** Use `str_replace` for existing files.
- **Validation:** Run shellcheck, verify bash syntax before saving.
- **Preserve:** Maintain existing indent, comment style, logic flow.
- **No hidden Unicode:** Strip U+202F, U+200B, U+00AD.
- **No trailing whitespace**

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

---

## Arch Build Environment

```bash
export CFLAGS="-march=native -mtune=native -O3 -pipe"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$(nproc)" NINJAFLAGS="-j$(nproc)"
export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat"
command -v ld.lld &>/dev/null && export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
```

---

## Network Operations

### Hardened Fetch

```bash
fetch_url(){
  local url=${1:?} out=${2:?}
  local -a curl_opts=(-fsSL --proto '=https' --tlsv1.3 --max-time 30 --retry 3 --retry-delay 2)
  if has aria2c; then
    aria2c -x16 -s16 --max-tries=3 --retry-wait=2 --max-connection-per-server=16 "$url" -o "$out"
  elif has curl; then
    curl "${curl_opts[@]}" -o "$out" "$url"
  elif has wget2; then
    wget2 --progress=bar --https-only --max-redirect=3 -O "$out" "$url"
  else
    wget --progress=bar --https-only --max-redirect=3 -O "$out" "$url"
  fi
}
```

### Git Operations

```bash
# Retry git operations with exponential backoff (network failures)
git_push(){
  local branch=${1:-$(git rev-parse --abbrev-ref HEAD)}
  retry 4 2 git push -u origin "$branch"
}

git_fetch(){
  local branch=${1:?}
  retry 4 2 git fetch origin "$branch"
}
```

---

## Device Operations (Pi & Imaging)

- Derive partition suffix: `[[ $dev == *@(nvme|mmcblk|loop)* ]] && p="${dev}p1" || p="${dev}1"`
- Wait for device nodes with retry loop
- Use `udevadm settle` when needed
- Always `umount -R` in cleanup
- Detach loop devices; ignore errors but log

---

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

---

## Data Processing Patterns

### Load Filtered Config/Package Lists

```bash
# Strip comments, trim whitespace, remove blank lines
mapfile -t arr < <(grep -Ev '^\s*(#|$)' file.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Alternative: Pure bash (slower but no deps)
load_config(){
  local -n out=$1
  local file=${2:?}
  local line
  while IFS= read -r line; do
    line=${line%%#*}  # Strip comments
    line=${line#"${line%%[![:space:]]*}"}  # Trim leading
    line=${line%"${line##*[![:space:]]}"}  # Trim trailing
    [[ -n $line ]] && out+=("$line")
  done < "$file"
}
```

### Batch Package Operations

```bash
# Install from list (prefer batching over loops)
printf '%s\n' "${arr[@]}" | $PKG_MGR -Sq --noconfirm

# Check installed with single invocation
check_installed(){
  local -n missing=$1
  shift
  local pkg
  for pkg; do
    pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
  done
}
```

### String Manipulation (Pure Bash)

```bash
# Upper/lowercase
upper="${str^^}"
lower="${str,,}"

# Replace (first/all)
new="${str/pattern/replacement}"     # First match
new="${str//pattern/replacement}"    # All matches

# Trim
trim="${str#"${str%%[![:space:]]*}"}"  # Leading
trim="${trim%"${trim##*[![:space:]]}"}"  # Trailing

# Split on delimiter
IFS=: read -ra parts <<< "$PATH"
```

---

## Testing Strategy

- **Unit:** `bats-core` for individual functions
- **Integration:** End-to-end scenarios on Arch/Debian
- **Static:** `shellcheck --severity=style`
- **Format:** `shfmt -i 2 -ci -sr`
- **Performance:** `hyperfine` for critical paths
- **Distro compat:** Test on Arch and Debian

---

## GitHub Infrastructure

### Workflows (@.github/workflows/)

| Workflow | Purpose | Trigger |
|:---------|:--------|:--------|
| `lint-format.yml` | ShellCheck, shfmt, Prettier, yamllint | Push/PR |
| `claude.yml` | Claude Code integration (@claude mentions) | Issue/PR/comment |
| `gemini-dispatch.yml` | Gemini API dispatch | PR/issue open |
| `gemini-review.yml` | Gemini code review | PR review |
| `deps.yml` | Dependabot dependency updates | Scheduled |

### AI Agents (@.github/agents/)

| Agent | Purpose |
|:------|:--------|
| `bash.agent.md` | Bash expert (modern, secure, performant) |
| `python.agent.md` | Production Python (strict typing, security) |
| `critical-thinking.agent.md` | Socratic logic probe |
| `github-issue-fixer.agent.md` | Issue resolution specialist |
| `refactoring-expert.agent.md` | Tech debt assassin |
| `repo-index.agent.md` | Repository indexing & briefing |
| `4.1-Beast.agent.md` | Autonomous advanced agent |

### Instructions (@.github/instructions/)

Guidance documents for: bash, python, code-review, task-implementation, performance-optimization, actions, memory-bank, token-efficient, markdown, prompt engineering.

---

## Architectural Analysis (Gemini Pattern)

### Comparison Format

```text
Approach A: [Description]
  ✅ Pro: [Benefit 1], [Benefit 2]
  ❌ Con: [Drawback 1], [Drawback 2]
  ⚡ Perf: [Performance characteristic]

Approach B: [Description]
  ✅ Pro: [Benefit 1], [Benefit 2]
  ❌ Con: [Drawback 1], [Drawback 2]
  ⚡ Perf: [Performance characteristic]

Recommendation: [Choice] ∵ [Key reason]
```

### Design Heuristics

- **Measure first:** Profile before optimizing.
- **Common case:** Optimize hot paths. Edge cases deprioritized.
- **Decomposition:** Break complex problems into analyzable units.
- **Constraint mapping:** Identify hard limits (latency, memory, cost).

### Performance Analysis Framework

**Backend:**

- Query patterns → connection pooling, caching strategy
- I/O bottlenecks → async, batch operations
- Scaling constraints → horizontal vs vertical, stateless design

**Infrastructure:**

- Latency budget → CDN, edge compute, regional deployment
- Cost structure → serverless vs containers vs VMs
- Reliability → failure modes, circuit breakers, degradation

---

## Security Best Practices

### Command Injection Prevention

```bash
# ✅ GOOD: Array expansion
local -a cmd=(pacman -S)
cmd+=("$pkg")
"${cmd[@]}"

# ✅ GOOD: Validated input
validate_pkg "$pkg"
pacman -S -- "$pkg"

# ❌ BAD: Direct expansion
eval "pacman -S $pkg"  # NEVER
```

### Path Traversal Prevention

```bash
validate_path(){
  local path=${1:?}
  [[ $path =~ ^[[:alnum:]/_.-]+$ ]] || die "invalid chars in path: $path"
  [[ ! $path =~ \.\. ]] || die "path traversal attempt: $path"
  [[ $path != /* ]] || die "absolute path not allowed: $path"
}
```

### Secure Temp Files

```bash
# ✅ GOOD: mktemp with proper permissions
TMPFILE=$(mktemp) || die "mktemp failed"
chmod 600 "$TMPFILE"

# ✅ GOOD: Atomic writes
printf '%s\n' "$content" > "${file}.tmp"
chmod 644 "${file}.tmp"
mv -f "${file}.tmp" "$file"

# ❌ BAD: Predictable names
TMPFILE="/tmp/script.$$"  # NEVER
```

## Error Handling Patterns

### Trap-Based Cleanup

```bash
cleanup(){
  set +e  # Don't exit on cleanup errors
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
```

### Context-Rich Errors

```bash
# ✅ GOOD: Contextual errors
pkg_install(){
  local pkg=${1:?missing package name}
  pacman -Q "$pkg" &>/dev/null && { warn "$pkg already installed"; return 0; }
  $PKG_MGR -S --noconfirm "$pkg" || die "failed to install $pkg (exit: $?)"
}

# ❌ BAD: Generic errors
pacman -S "$pkg" || die "install failed"
```

---

## Common Patterns

### Locking

```bash
lock(){
  local key=${1:?}
  local lockfile="/run/lock/${key//[^[:alnum:]]/_}.lock"
  exec {LOCK_FD}>"$lockfile" || die "lock fd failed for $key"
  flock -n "$LOCK_FD" || die "lock taken: $key (${lockfile})"
}
```

### Retry with Exponential Backoff

```bash
retry(){
  local -i max=${1:?}
  local -i delay=${2:-2}
  local -i attempt=0
  shift 2
  until "$@"; do
    (( ++attempt >= max )) && die "failed after $max attempts: $*"
    warn "attempt $attempt/$max failed, retrying in ${delay}s..."
    sleep "$delay"
    (( delay *= 2 ))
  done
}
# Usage: retry 4 2 git push origin main
```

### Input Validation

```bash
validate_path(){
  local path=${1:?}
  [[ $path =~ ^[[:alnum:]/_.-]+$ ]] || die "invalid path: $path"
  [[ ! $path =~ \.\. ]] || die "path traversal detected: $path"
}

validate_pkg(){
  local pkg=${1:?}
  [[ $pkg =~ ^[a-z0-9@._+-]+$ ]] || die "invalid package name: $pkg"
}
```

### Interactive Selection with fzf

```bash
select_file(){
  local -n result=$1
  local pattern=${2:-'.*'}
  if [[ -n $FD ]]; then
    result=$("$FD" -H -t f "$pattern" | fzf --prompt="Select file: " --preview 'bat --color=always {}')
  else
    result=$(find . -type f -name "*${pattern}*" | fzf --prompt="Select file: ")
  fi
  [[ -n $result ]] || die "no file selected"
}
```

### Safe URL Fetching

```bash
fetch(){
  local url=${1:?} out=${2:?}
  validate_path "$out"
  local -a curl_opts=(-fsSL --proto '=https' --tlsv1.3 --max-time 30)
  if has aria2c; then
    aria2c -x16 -s16 --max-tries=3 --retry-wait=2 "$url" -o "$out"
  elif has curl; then
    retry 3 2 curl "${curl_opts[@]}" -o "$out" "$url"
  elif has wget2; then
    retry 3 2 wget2 --progress=bar --max-redirect=3 -O "$out" "$url"
  else
    retry 3 2 wget --progress=bar --max-redirect=3 -O "$out" "$url"
  fi
}
```

### Parallel Execution

```bash
parallel_exec(){
  local -a jobs=("$@")
  if has rust-parallel; then
    printf '%s\n' "${jobs[@]}" | rust-parallel -j"$(nproc)"
  elif has parallel; then
    printf '%s\n' "${jobs[@]}" | parallel -j"$(nproc)"
  else
    printf '%s\n' "${jobs[@]}" | xargs -r -P"$(nproc)" -I{} bash -c '{}'
  fi
}
```

---

## Key Scripts Reference

### Cachyos/

| Script | Purpose |
|:-------|:--------|
| @Cachyos/up.sh | All-in-one update orchestrator (pacman, flatpak, rust, npm, etc.) |
| @Cachyos/clean.sh | Comprehensive cleanup: cache, orphans, logs, browser data |
| @Cachyos/setup.sh | Automated system configuration |
| @Cachyos/Rank.sh | Mirror ranking + keyring updates |
| @Cachyos/debloat.sh | Remove bloatware and services |
| @Cachyos/rustbuild.sh | Rust compilation environment |

### RaspberryPi/

| Script | Purpose |
|:-------|:--------|
| @RaspberryPi/raspi-f2fs.sh | F2FS imaging orchestrator (loop devices, partitioning) |
| @RaspberryPi/update.sh | Pi-specific APT update |
| @RaspberryPi/PiClean.sh | Pi cleanup automation |
| @RaspberryPi/Scripts/setup.sh | Initial Pi setup & optimization |
| @RaspberryPi/Scripts/Kbuild.sh | Kernel building automation |
| @RaspberryPi/Scripts/apkg.sh | Interactive fzf/skim APT manager |

---

## ShellCheck Configuration

Located in @.shellcheckrc:

- Shell: bash
- External sources enabled
- Source path: SCRIPTDIR
- Disabled checks: SC1079, SC1078, SC1073, SC1072, SC1083, SC2086, SC1090, SC1091, SC2002, SC2016, SC2034, SC2154, SC2155, SC2236, SC2250, SC2312

---

## EditorConfig

Located in @.editorconfig:

- **Default indent:** 2 spaces
- **Line endings:** LF
- **Charset:** UTF-8
- **Max line length:** 120 (general), 100 (Rust/C++), 88 (Python), 80 (Markdown)
- **Shell scripts:** 2-space indent, bash variant
- **Trailing whitespace:** Trimmed (except Markdown)
- **Final newline:** Required

---

## Review Checklist

Before committing, verify:

### Script Structure

- [ ] Starts with `#!/usr/bin/env bash`
- [ ] Has `set -Eeuo pipefail` and shopt flags (`nullglob globstar extglob dotglob`)
- [ ] Sets `IFS=$'\n\t'` and `LC_ALL=C LANG=C`
- [ ] Traps for `EXIT` (cleanup), `ERR` (line numbers), `INT TERM` (interrupts)
- [ ] Cleanup function with `set +e` and proper resource release
- [ ] Uses script template from this document

### Best Practices

- [ ] Uses arrays/mapfile/`[[ ... ]]` and parameter expansion
- [ ] Avoids forbidden patterns: parsing `ls`, `eval`, backticks, `for x in $(cmd)`
- [ ] Quotes all variables except intentional glob/split
- [ ] Logging helpers present: `has()`, `log()`, `warn()`, `err()`, `die()`, `dbg()`
- [ ] Color palette defined (trans flag colors)
- [ ] Uses `printf` over `echo` for output
- [ ] Namerefs for output parameters: `local -n result=$1`

### Security & Safety

- [ ] Input validation (paths, package names, URLs)
- [ ] No command injection vulnerabilities
- [ ] No path traversal vulnerabilities
- [ ] Secure temp files with `mktemp` and proper permissions
- [ ] No hardcoded `sudo` or root assumptions

### Tool & Compatibility

- [ ] Package manager detection (`paru`→`yay`→`pacman` / `apt`)
- [ ] Rust tools preferred with fallbacks (`fd`→`find`, `rg`→`grep`, `bat`→`cat`)
- [ ] Arch/Debian paths handled where applicable
- [ ] Network operations use retry logic for failures
- [ ] Git operations use exponential backoff retry (4 attempts, 2s base)

### Interface & UX

- [ ] Flags parsed via short options (`-q -v -y -o -h`)
- [ ] Supports `--help` and `--version`
- [ ] Config as associative array: `declare -A cfg=([key]=val)`
- [ ] Dry-run support: `run()` wrapper
- [ ] Contextual error messages with exit codes

### Performance

- [ ] Batch operations over loops where possible
- [ ] Minimal external calls (use builtins: `${var##*/}` not `basename`)
- [ ] Parallelized safely with `xargs -P` or `rust-parallel`
- [ ] No unnecessary forks/subshells
- [ ] Anchored regexes: `^pattern$`
- [ ] Literal search where possible: `grep -F`, `rg -F`

### Quality

- [ ] Linted with `shellcheck --severity=style` (zero warnings)
- [ ] Formatted with `shfmt -i 2 -ci -sr`
- [ ] Tests pass (if applicable): `bats-core` unit, integration
- [ ] Benchmarked hot paths with `hyperfine` (if performance-critical)
- [ ] No trailing whitespace
- [ ] No hidden Unicode characters (U+202F, U+200B, U+00AD)
- [ ] Follows single responsibility principle
- [ ] Clear intent (self-documenting code)

---

## Quick Reference

### Common Operations

```bash
# Check if package installed
pacman -Q "$pkg" &>/dev/null || install_package "$pkg"

# Batch install
printf '%s\n' "${pkgs[@]}" | $PKG_MGR -Sq --noconfirm

# Safe fetch with retry
retry 3 2 curl -fsSL --proto '=https' --tlsv1.3 -o "$out" "$url"

# Parallel execution
printf '%s\n' "${items[@]}" | xargs -r -P"$(nproc)" -I{} process {}

# Lock management
exec {LOCK_FD}>"/run/lock/myapp.lock"
flock -n "$LOCK_FD" || die "already running"

# Input validation
[[ $path =~ ^[[:alnum:]/_.-]+$ ]] || die "invalid path"
[[ ! $path =~ \.\. ]] || die "path traversal detected"

# String manipulation
name=${file##*/}           # basename
dir=${file%/*}             # dirname
ext=${file##*.}            # extension
base=${file%.*}            # remove extension
upper=${str^^}             # uppercase
lower=${str,,}             # lowercase
```

### Exit Codes

- `0` - Success
- `1` - General error
- `2` - Misuse of shell builtins
- `126` - Command cannot execute
- `127` - Command not found
- `130` - Script terminated by Ctrl+C
- `255` - Exit status out of range

---

## References

- **Bash Manual:** <https://www.gnu.org/software/bash/manual/>
- **Google Shell Style:** <https://google.github.io/styleguide/shellguide.html>
- **ShellCheck:** <https://www.shellcheck.net/wiki/>
- **Pure Bash Bible:** <https://github.com/dylanaraps/pure-bash-bible>
- **EditorConfig:** <https://editorconfig.org/>
- **CachyOS:** <https://cachyos.org/>
- **Arch Wiki:** <https://wiki.archlinux.org/>

---

## Design Principles

1. **Single Responsibility:** Functions do one thing well
2. **Loose Coupling:** Minimize dependencies between components
3. **Early Returns:** Exit fast on errors or edge cases
4. **Avoid Over-Abstraction:** Don't generalize prematurely
5. **Eliminate Duplication:** Reuse patterns from script template and @Shell-book.md
6. **Clear Intent:** Code should be self-documenting; comment only for "why" not "what"

---

*This document is the unified source for AI assistant guidelines.*
*@CLAUDE.md and @GEMINI.md symlink here for compatibility.*
