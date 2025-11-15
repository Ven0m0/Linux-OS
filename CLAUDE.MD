# Claude Instructions: Linux-OS

## Repository Overview

**Linux-OS** is a comprehensive collection of scripts and resources for managing, optimizing, and customizing Linux distributions, with primary focus on Arch-based systems (CachyOS, EndeavourOS) and Raspberry Pi self-hosting. The repository contains 100+ shell scripts emphasizing performance optimization, privacy hardening, and modern tooling.

**Statistics**: 100 shell scripts | 89 config/documentation files | ~273 lines eliminated via lib/common.sh

**Recent Focus**: Parallel execution optimization (commit: e4c56c6), Podman/Docker improvements

## Core Directives
Autonomous execution. Minimal confirmations. Token-efficient responses. Primary focus: Bash scripts & system configs.

## Operating Principles
- **Direct Execution**: Edit files immediately without requesting permission
- **Confirm Only Critical Changes**: Wide-scope architectural changes only
- **Quality-Driven**: Thorough validation, best practices, fact verification
- **Edit Over Create**: Modify existing files preferentially
- **Multi-Approach Analysis**: Compare pros/cons when multiple solutions exist
- **Efficient Planning**: Outline complex approaches before implementation

### Communication Style
Language: Technical English | Tone: Professional, concise | Complexity: Advanced | Emojis: Minimal usage | Naming: Brief, clear

### Abbreviations Reference
y=Yes n=No c=Continue r=Review u=Undo | cfg=config impl=implementation arch=architecture deps=dependencies val=validation sec=security err=error opt=optimization Δ=change mgr=manager fn=function mod=modify rm=remove w/=with dup=duplicate

## Repository Structure

```
/home/user/Linux-OS/
├── .github/                    # GitHub automation & AI configuration
│   ├── agents/                 # AI agent definitions (bash-architect, performance-engineer, etc.)
│   ├── chatmodes/              # Conversational AI modes
│   ├── copilot/                # GitHub Copilot instructions
│   ├── instructions/           # Language-specific guidelines (bash, rust, python, etc.)
│   ├── prompts/                # Prompt templates
│   └── workflows/              # CI/CD (shell.yml, mega-linter.yml, etc.)
├── Cachyos/                    # CachyOS/Arch-based distribution scripts
│   ├── lib/common.sh           # Shared functions library (15,945 bytes, DRY principle)
│   ├── Updates.sh              # System update automation
│   ├── Clean.sh                # System cleanup & maintenance
│   ├── Rank.sh                 # Mirror ranking & optimization
│   ├── archmaint.sh            # Comprehensive Arch maintenance (705 lines)
│   ├── Firefox/                # Firefox configuration & telemetry scripts
│   ├── Rust/                   # Rust build optimization
│   └── Scripts/                # Main automation scripts
│       ├── Install.sh          # Automated package installation
│       ├── AutoSetup.sh        # System configuration automation
│       ├── Privacy-Config.sh   # Privacy hardening
│       ├── Android/            # Android device optimization
│       ├── MC/                 # Minecraft server management
│       ├── WIP/                # Work-in-progress scripts
│       ├── other/              # Miscellaneous utilities
│       └── shell-tools/        # Shell utility scripts
├── RaspberryPi/                # Raspberry Pi specific scripts
│   ├── lib/                    # Pi-specific libraries (common.sh, cleaning.sh, text.sh)
│   ├── update.sh               # Pi system updates
│   ├── PiClean.sh              # Pi cleanup utilities
│   ├── raspi-f2fs.sh           # F2FS filesystem conversion (1,032 lines)
│   ├── Scripts/Setup.sh        # Pi server setup (15,194 bytes)
│   └── dots/                   # Configuration files (apt.conf, apt-fast.conf)
├── Scripts/                    # General cross-platform scripts
├── Linux-Settings/             # System configuration references (Compiler.txt, Kernel.txt)
├── CLAUDE.MD                   # AI assistant instructions (this file)
├── Shell-book.md               # Bash scripting reference (14,406 bytes)
├── USEFUL.MD                   # Curated resources & compiler flags
└── README.md                   # Quick-start guide with curl-able commands
```

## Key Files & Components

### Critical Scripts (curl-able from README.md)
- **Cachyos/Updates.sh** (169 lines) - System update automation
- **Cachyos/Clean.sh** (208 lines) - System cleanup with smart cache management
- **Cachyos/Rank.sh** (322 lines) - Mirror ranking with parallel testing
- **Cachyos/archmaint.sh** (705 lines) - Comprehensive maintenance suite
- **Cachyos/Scripts/Install.sh** (10,083 bytes) - Automated package installation
- **Cachyos/Scripts/AutoSetup.sh** (10,437 bytes) - System configuration
- **RaspberryPi/raspi-f2fs.sh** (1,032 lines) - F2FS conversion utility

### Library System (DRY Principle)
**Cachyos/lib/common.sh** (15,945 bytes) - Eliminates ~273 lines of duplication across 8 scripts
- Color definitions & utility functions
- Package manager detection (paru → yay → pacman)
- Error handling patterns
- Common operation functions

**RaspberryPi/lib/** - Pi-specific libraries
- `common.sh` (4,952 bytes) - Core utilities
- `cleaning.sh` (4,701 bytes) - Cleaning functions
- `text.sh` (3,701 bytes) - Banner/text utilities

### Configuration Files
- **.editorconfig** - Universal formatting (shfmt, 2-space indent, bash variant detection)
- **.shellcheckrc** - Linting rules (enable=all, specific exclusions: SC2086, SC1090/1091)
- **.gitattributes** (2,381 bytes) - Git file handling
- **.gitignore** (2,160 bytes) - Security files, build artifacts, editor configs

### Documentation Structure
- **README.md** - Quick-start with curl commands
- **CLAUDE.MD** - AI assistant development guide (this file)
- **Shell-book.md** (14,406 bytes) - Bash reference, templates, snippets
- **USEFUL.MD** (1,971 bytes) - Compiler flags, external resources
- **GEMINI.MD** (6,119 bytes) - Additional AI instructions
- **todo.md** - Project task tracking

## Bash Script Standards

### Canonical Template
```bash
#!/usr/bin/env bash
export LC_ALL=C LANG=C

# Color definitions
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Utility functions
has() { command -v "$1" &>/dev/null; }
```

### Error Handling
Use strict mode judiciously:
```bash
set -euo pipefail  # Use for critical scripts
# OR
set -eo pipefail   # Use when unset variables are acceptable
```

### Sourcing Library
```bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" || {
  echo "Failed to load common library" >&2
  exit 1
}
```

## Code Patterns

### Package Management
- **Detection Chain**: `paru` → `yay` → `pacman` (Arch-based) | `apt`/`nala` (Debian-based)
- **Pre-Installation Checks**: `pacman -Q pkg` | `flatpak list` | `cargo install --list`
- **Distro-Specific Hints**: Include installation commands for both ecosystems
  - Example: `(Arch: pacman -S tool)` `(Debian: apt-get install -y tool)`

### Data Handling & Performance
- **Array Population**: `mapfile -t arr < <(command)` — avoids subshell performance penalties
- **Prohibitions**: Never parse `ls` output
- **Associative Arrays**: `declare -A cfg=([dry_run]=0 [debug]=0 [verbose]=0)`
- **Modern Tool Preferences** (Rust-based when available):
  - File finding: `fd`/`fdf` → `find` (use find for -exec operations)
  - Text search: `rg` (ripgrep) → `grep`
  - File viewing: `bat` → `cat`
  - Text substitution: `sd` → `sed`
  - Directory listing: `eza` → `ls`
  - Disk usage: `dust` → `du`
  - Download: `aria2` → `curl` → `wget2` → `wget` (no aria2 for piped output)
  - JSON processing: `jaq` → `jq`
  - Fuzzy selection: `sk` (skim) → `fzf`
  - Parallelization: `rust-parallel` → `parallel` → `xargs`
- **Optimization Focus**: Batch operations, minimize subprocess spawning, parallel execution

### Interactive Mode
- **Fuzzy Finder Integration**: Use fzf/skim for path selection when args missing
- **Fallback Pattern**: `has fd && fd -t f | fzf || find . -type f | fzf`
- **AUR Helper Flags**: `--needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --batchinstall`

### Network Operations
- **Standard Flags**: `curl -fsL --http2` (fail silently, show errors, follow redirects, HTTP/2)
- **Documentation**: Update README.md curl snippets when modifying script entrypoints

## Tooling Standards

### Code Quality Pipeline
All scripts must pass this pipeline before commit:
```bash
shfmt -i 2 -ln bash -bn -s file.sh && \
shellcheck -f diff file.sh | patch -Np1 && \
shellharden --replace file.sh
```

**Tool Purposes**:
- `shfmt`: Format with 2-space indent, simplify code, bash language mode
- `shellcheck`: Static analysis (enable=all with documented exclusions)
- `shellharden`: Security hardening (quote variables, escape strings)

### ShellCheck Exclusions (see .shellcheckrc)
Disabled checks with justification:
- **SC2086**: Word splitting desired for specific use cases
- **SC1090/1091**: Dynamic source paths (source resolution follows SCRIPTDIR)
- **SC2002**: Useless cat (acceptable for readability in pipelines)
- **SC2016**: Expressions in single quotes (intentional for heredocs)
- **SC2034/SC2154**: Unused/unassigned variables (used in sourced scripts)
- **SC2155**: Declare and assign separately (acceptable for simple cases)
- **SC2236/SC2250**: Use -n/-z for string tests (legacy compatibility)
- **SC2312**: Masking return values (intentional in specific contexts)

### Tool Fallback Chains
```bash
# File operations
has fdf && fdf ... || has fd && fd ... || find ...

# Downloads (no aria2 for piping)
has curl && curl -fsL ... || has wget && wget -qO- ...

# Parallelization
has rust-parallel && rust-parallel ... || has parallel && parallel ... || xargs -P4 ...

# JSON processing
has jaq && jaq ... || jq ...
```

## Development Practices

### Test-Driven Development
Process: Write failing test (Red) → Implement minimal passing code (Green) → Refactor for quality

### Change Classification
- **Structural**: Organization, formatting (no behavior changes)
- **Behavioral**: Function addition, modification, deletion
- **Rule**: Never mix in same commit

### Commit Requirements
All must be true: Tests pass | Zero warnings | Single logical unit | Clear message
Preference: Small, frequent, independent commits

**Recent Commit Pattern**:
- Performance optimizations (parallel execution)
- Container tooling updates (Podman)
- Single-purpose changes

### Code Quality Standards
- Single responsibility per function/module
- Loose coupling via interfaces
- Early returns for clarity
- Avoid premature abstraction
- Eliminate duplication immediately (use lib/common.sh)
- Explicit dependencies, clear intent
- Small, focused functions (<50 lines preferred)

### Prohibited Patterns
❌ Hardcoded values (use constants/config/environment)
❌ Repetitive code blocks (create functions or use lib/common.sh)
❌ Duplicated error handling (unify patterns)
❌ Replicated logic (abstract to library)
❌ Parsing `ls` output (use globs, arrays, or find)
❌ Unnecessary subshells (use mapfile, process substitution)

## CI/CD & Code Quality

### GitHub Actions Workflows (.github/workflows/)

**shell.yml** - Shell script linting
- Triggers: Push to main/master, PRs, manual dispatch
- Excludes: `.git/`, `Linux-Settings/`
- Uses: Reusable shell linting workflow

**mega-linter.yml** - Multi-language linting
- Linters: YAML, TOML, JSON, JSON5, JSONC, properties
- Triggers: Push to main/master/claude/**, PRs
- Excludes: `.github`, `.git`, `.cache`, `node_modules`, `.rustup`

**Additional Workflows**:
- `aio.yml` - All-in-one workflow
- `img-opt.yml` - Image optimization
- `update-git-submodules.yml` - Automated submodule updates
- `automerge-dependabot.yml` - Dependency automation

### Pre-commit Checklist
1. Run code quality pipeline (shfmt → shellcheck → shellharden)
2. Test script functionality (dry-run if available)
3. Update README.md if entrypoint changed
4. Update lib/common.sh if creating reusable functions
5. Verify no sensitive data committed (.env, tokens, keys)
6. Single logical change per commit

### Deployment Method
Scripts are curl-able from GitHub main branch:
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/path/to/script.sh | bash
```

## Build Optimization & Toolchain

### Compiler Flags (see Linux-Settings/Compiler.txt)
- **Toolchain**: LLVM/Clang preferred, GCC fallback
- **Linker**: `mold` → `lld` → `gold` → `ld`
- **Caching**: `sccache` (Rust), `ccache` (C/C++)
- **Optimization**: LTO, PGO for critical builds

### Rust Build Optimization (see Cachyos/Rust/)
- Strip debug symbols from installed binaries
- Profile-guided optimization for hot paths
- Parallel compilation with jobserver
- Target CPU optimization flags

## Agent System
Available specialized agents (see `.github/agents.yml`):
- **bash-architect**: Script design & architecture
- **performance-engineer**: Profiling & optimization
- **config-specialist**: Configuration management
- **security-specialist**: Security audit & hardening
- **documentation-expert**: Technical writing
- **code-janitor**: Code cleanup & refactoring

Invoke: `@agent-name [task]`

## Chat Modes
Available modes (see `.github/chat-modes.yml`):
- `quick-fix`: Fast bug fixes
- `refactor`: Code quality improvement
- `feature`: New feature development
- `debug`: Problem investigation
- `optimize`: Performance tuning
- `review`: Code quality assessment
- `explain`: Concept explanation
- `script`: Script generation

Activate: `/mode [mode-name]`

## Prompt Templates
Common templates (see `.github/prompt-templates.yml`):
- `optimize-script`: Performance optimization
- `add-error-handling`: Error handling patterns
- `make-distro-agnostic`: Multi-distro support
- `add-interactive-mode`: fzf integration
- `security-audit`: Security review
- `write-tests`: Test generation
- `generate-readme`: Documentation
- `modernize-tools`: Tool upgrades (replace GNU with Rust tools)
- `add-dry-run`: Safe preview mode
- `parallel-processing`: Concurrent execution

Use: `/template [template-name]`

## Supported Distributions

**Primary**:
- CachyOS (Arch-based, performance-optimized kernel)
- EndeavourOS (Arch-based, user-friendly)
- Raspberry Pi OS (Debian-based, ARM)

**Secondary**:
- Nobara, SteamOS, Bazzite (Gaming-focused)
- Gentoo (Source-based)
- Linux Mint (Debian/Ubuntu-based)
- DietPi (Minimal for SBCs)

## Security Considerations

### Privacy & Hardening
- Firefox telemetry removal (Cachyos/Firefox/)
- Privacy configuration scripts (Privacy-Config.sh)
- Debloating utilities (Debloat.sh)
- Pi-hole ad blocking (RaspberryPi/Scripts/)

### Secure Coding Practices
- Quote all variables unless word splitting intended
- Validate user input before execution
- Use `--` to separate options from arguments
- Avoid `eval` except when absolutely necessary
- Set appropriate file permissions (644 for data, 755 for scripts)
- Never log sensitive information

---

**Last Updated**: 2025-11-15 (commit: e4c56c6 - parallel execution optimizations)
**Maintainer**: Ven0m0
**Contributors**: copilot-swe-agent[bot], Claude

*Optimized for Claude's context window and reasoning capabilities*
