# Gemini Instructions: Linux-OS

## Primary Directive
Execute autonomously. Minimize confirmations. Maximize token efficiency. Focus: Bash scripting & system configuration.

## Core Principles
1. **Immediate Execution** — Modify existing files without hesitation
2. **Selective Confirmation** — Only for wide-impact architectural changes
3. **Quality Assurance** — Validate thoroughly, verify facts, follow best practices
4. **Edit-First Approach** — Prefer modifying existing files over creating new ones
5. **Solution Comparison** — When multiple approaches exist, present pros/cons
6. **Efficient Workflow** — Draft approach before complex implementation

## Communication Standards
- **Language**: Technical English
- **Style**: Professional, concise, advanced level
- **Emojis**: Minimal usage only
- **Naming**: Short, clear identifiers

## Abbreviation Dictionary
Quick responses: `y`=Yes `n`=No `c`=Continue `r`=Review `u`=Undo

Common terms: cfg=config | impl=implementation | arch=architecture | deps=dependencies | val=validation | sec=security | err=error | opt=optimization | Δ=change | mgr=manager | fn=function | mod=modify | rm=remove | w/=with | dup=duplicate

## Bash Scripting Standards

### Standard Script Header
```bash
#!/usr/bin/env bash
export LC_ALL=C LANG=C

# Terminal colors and formatting
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Core utility function
has() { command -v "$1" &>/dev/null; }
```

## Implementation Patterns

### Package Management

**Detection Priority**:
- Arch ecosystem: `paru` → `yay` → `pacman`
- Debian ecosystem: `apt` → `dpkg`
- Store in `pkgmgr` array for multi-distro support

**Pre-Installation Verification**:
- Pacman packages: `pacman -Q package_name`
- Flatpak apps: `flatpak list`
- Cargo binaries: `cargo install --list`

**Documentation Format**:
Include distro-specific installation hints:
- `(Arch: pacman -S package_name)`
- `(Debian: apt-get install -y package_name)`

### Data Handling & Optimization

**Efficient Array Population**:
```bash
mapfile -t array < <(command)  # Avoids subshell overhead
```

**Critical Rules**:
- ❌ Never parse `ls` output
- ✅ Use associative arrays for configuration: `declare -A cfg=([key]=value)`

**Tool Preference Hierarchy**:
| Task | Primary | Fallback 1 | Fallback 2 |
|------|---------|------------|------------|
| File search | `fd` | `find` | - |
| Text search | `rg` | `grep` | - |
| File display | `bat` | `cat` | - |
| Text replacement | `sd` | `sed` | - |
| Download | `aria2` | `curl` | `wget` |
| JSON processing | `jaq` | `jq` | - |
| Fuzzy finding | `sk` | `fzf` | - |

**Performance Guidelines**:
- Batch operations whenever possible
- Minimize subprocess spawning
- Use process substitution over pipes for complex chains

### Interactive Features

**Fuzzy Finder Integration**:
- Trigger when required arguments (paths) are missing
- Fallback pattern:
  ```bash
  has fd && fd -t f | fzf || find . -type f | fzf
  ```

**AUR Helper Configuration**:
Standard flags: `--needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --batchinstall`

### Network Operations

**Standard cURL Configuration**:
```bash
curl -fsL --http2 <url>
```

**Maintenance Requirement**:
Update README curl snippets when modifying entrypoint scripts

## Quality Assurance Tools

### Code Formatting & Validation Pipeline
```bash
# Format with shfmt
shfmt -i 2 -ln bash -bn -s file.sh && \

# Lint with shellcheck (apply suggestions)
shellcheck -f diff file.sh | patch -Np1 && \

# Harden with shellharden
shellharden --replace file.sh
```

### Modern Tool Fallback Matrix
- **File discovery**: `fdf` → `fd` → `find` (note: prefer `find` for `-exec` operations)
- **Download operations**: `aria2` → `curl` → `wget2` → `wget` (exclude aria2 for piped operations)
- **Parallel execution**: `rust-parallel` → `parallel` → `xargs`

## Development Methodology

### Test-Driven Development Cycle
1. **Red Phase**: Write failing test
2. **Green Phase**: Implement minimal code to pass
3. **Refactor Phase**: Improve code quality while maintaining passing tests

### Change Type Separation

**Structural Changes**:
- Code organization
- Formatting adjustments
- No behavioral modifications

**Behavioral Changes**:
- Function addition
- Logic modification
- Feature deletion

**Critical Rule**: Never mix structural and behavioral changes in the same commit

### Commit Standards

**Prerequisites** (all required):
- ✅ All tests passing
- ✅ Zero warnings
- ✅ Single logical unit of work
- ✅ Clear, descriptive commit message

**Best Practices**:
- Prefer small commits over large ones
- Commit frequently
- Ensure each commit is independent and atomic

### Code Quality Checklist
- [ ] Single responsibility principle per function/module
- [ ] Loose coupling through interface design
- [ ] Early returns for improved readability
- [ ] Avoid over-abstraction
- [ ] Eliminate code duplication immediately
- [ ] Clear intent with explicit dependencies
- [ ] Small, focused, single-responsibility functions

### Anti-Patterns (Prohibited)
1. ❌ **Hardcoded Values**: Use constants, configuration files, or environment variables
2. ❌ **Repetitive Code**: Extract into reusable functions
3. ❌ **Common Error Handling**: Unify error patterns
4. ❌ **Duplicated Logic**: Abstract into shared utilities

## Symbol System

### Flow Indicators
- `→` leads to
- `⇒` converts to
- `←` rollback
- `⇄` bidirectional
- `&` logical and
- `|` logical or
- `»` then/next
- `∴` therefore
- `∵` because

### Status Markers
- ✅ completed
- ❌ failed
- ⚠️ warning
- 🔄 in progress
- ⏳ pending
- 🚨 critical issue

### Domain Categories
- ⚡ performance
- 🔍 code analysis
- 🔧 configuration
- 🛡️ security
- 📦 deployment
- 🎨 user interface
- 🏗️ architecture
- 🗄️ database
- ⚙️ backend
- 🧪 testing

---

*Optimized for Gemini's multimodal capabilities and structured reasoning*
