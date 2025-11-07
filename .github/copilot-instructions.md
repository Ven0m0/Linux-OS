# Copilot Instructions: Linux-OS

## Core
Autonomous exec. Min confirms. Max token efficiency. Bash & cfg focus.

## Principles
**Exec Immediately** — Edit existing w/o hesitation | **Confirm Large Δ Only** | **Quality First** — Auto checks | **Verify Facts** — No speculation | **Prefer Existing** → Edit over create | **Rethink** — List pros/cons if ≥2 approaches

### Settings
Lang: EN (tech) | Style: Pro, concise, advanced | Emojis: Min | Names: short

### Abbrev
`y`=Yes `n`=No `c`=Cont `r`=Rev `u`=Undo | cfg=config impl=implementation arch=architecture deps=dependencies val=validation sec=security err=error opt=optimization Δ=change mgr=manager fn=function mod=modify rm=remove w/=with dup=duplicate

## Bash Template
```bash
#!/usr/bin/env bash
export LC_ALL=C LANG=C
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m' LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m' DEF=$'\e[0m' BLD=$'\e[1m'
has() { command -v "$1" &>/dev/null; }
```

## Code Patterns
### Pkg Mgrs & Privilege
Detect: `paru`→`yay`→`pacman` (Arch) | `apt`/`dpkg` (Debian) → `pkgmgr` array | Check before install: `pacman -Q pkg`, `flatpak list`, `cargo install --list` | Distro hints: `(Arch: pacman -S pkg)` `(Debian: apt-get install -y pkg)`

### Data & Performance
`mapfile -t arr < <(cmd)` avoid subshells | Never parse `ls` | Assoc arrays: `declare -A cfg=([dry_run]=0 [debug]=0)` | Prefer modern tools: `fd`→`find` `rg`→`grep` `bat`→`cat` `sd`→`sed` `aria2`→`curl`→`wget` `jaq`→`jq` `sk`→`fzf` | Batch ops, reduce subprocess spawning

### Interactive
Arg-less w/ fzf when paths missing | Fallback: `has fd && fd ... | fzf || find ... | fzf` | AUR: `--needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --batchinstall`

### Network
`curl -fsL --http2` | Update README curl snippets on entrypoint mod

## Tooling
**Fmt/Lint/Harden**: `shfmt -i 2 -ln bash -bn -s file.sh && shellcheck -f diff file.sh | patch -Np1 && shellharden --replace file.sh`

**Modern w/ Fallbacks**: `fdf`→`fd`→`find` (no exec) | `aria2`→`curl`→`wget2`→`wget` (no aria2 if pipe) | `rust-parallel`→`parallel`→`xargs`

## Dev Practices
**TDD**: Red→Green→Refactor | **Changes**: Structural (fmt/org) ≠ Behavioral (fn add/mod/del) — never mix | **Commit**: Tests pass + Zero warns + Single unit + Clear msg — small, frequent, independent | **Quality**: Single responsibility, loose coupling, early returns, no over-abstraction, elim dup, clear intent, explicit deps

### Prohibitions
❌ Hardcode (use const/cfg/env) | ❌ Repetitive (functionize) | ❌ Common err (unify) | ❌ Dup logic (abstract)

## Agents
See `copilot-agents.yml`:
- **bash-expert**: Bash scripting specialist
- **performance-optimizer**: Performance tuning
- **config-manager**: Config files
- **security-auditor**: Security review
- **doc-writer**: Documentation

Invoke via Copilot Chat: `@workspace /agent bash-expert`

## Symbols
→ leads | ⇒ converts | ← rollback | ⇄ bidir | & and | \| or | » then | ∴ therefore | ∵ because | ✅ done | ❌ fail | ⚠️ warn | 🔄 active | ⏳ pending | 🚨 critical | ⚡ perf | 🔍 analysis | 🔧 cfg | 🛡️ sec | 📦 deploy | 🎨 UI | 🏗️ arch | 🗄️ DB | ⚙️ backend | 🧪 test
