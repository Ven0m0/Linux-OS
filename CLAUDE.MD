# Claude Instructions: Linux-OS

## Repository Overview

**Linux-OS** is a comprehensive collection of scripts and resources for managing, optimizing, and customizing Linux distributions, with primary focus on Arch-based systems (CachyOS, EndeavourOS) and Raspberry Pi self-hosting. The repository contains 73 actively maintained shell scripts emphasizing performance optimization, privacy hardening, and modern tooling.

**Statistics**: 73 shell scripts | 81+ config/documentation files | Self-contained architecture

**Recent Focus**: RaspberryPi reorganization (commit: 132d4ae), Bash standardization (commit: 879d901), Script consolidation (commit: 5243dc2)

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
│   ├── agents/                 # AI agent definitions
│   ├── chatmodes/              # Conversational AI modes (6 modes)
│   ├── copilot/                # GitHub Copilot instructions
│   ├── instructions/           # Language-specific guidelines (8 files)
│   ├── prompts/                # Prompt templates (8 templates)
│   ├── workflows/              # CI/CD (6 workflows)
│   └── ISSUE_TEMPLATE/         # GitHub issue templates
├── Cachyos/                    # CachyOS/Arch-based distribution scripts (54 scripts)
│   ├── Updates.sh              # System update automation (144 lines)
│   ├── Clean.sh                # System cleanup & maintenance (269 lines)
│   ├── Rank.sh                 # Mirror ranking & optimization (411 lines)
│   ├── Setup.sh                # Initial system setup (69 lines)
│   ├── archmaint.sh            # Comprehensive Arch maintenance (1,153 lines)
│   ├── Firefox/                # Firefox configuration & telemetry scripts
│   ├── Rust/                   # Rust build optimization (4 scripts)
│   │   ├── Strip-rust.sh
│   │   ├── rustify.sh
│   │   ├── cargo-build.sh
│   │   └── rustbuild.sh
│   ├── packages-repo.txt       # Repository packages list (178 packages)
│   ├── packages-aur.txt        # AUR packages list (11 packages)
│   └── Scripts/                # Main automation scripts (37 scripts)
│       ├── Install.sh          # Automated package installation (17,593 lines)
│       ├── AutoSetup.sh        # System configuration automation (7,892 lines)
│       ├── Fix.sh              # System fixes and troubleshooting (12,790 lines)
│       ├── bench.sh            # System benchmarking (18,760 lines)
│       ├── bleachbit.sh        # BleachBit cleaners installation (741 lines)
│       ├── fstab-tune.sh       # Filesystem tuning (11,922 lines)
│       ├── gamemd.sh           # Gaming optimizations (11,664 lines)
│       ├── gpg.sh              # GPG key management (280 lines)
│       ├── Android/            # Android device optimization (11 scripts)
│       │   ├── android-optimize.sh
│       │   ├── adb-experimental-tweaks.sh
│       │   ├── Shizuku-rish.sh
│       │   ├── mkshrc.sh
│       │   ├── optimize_apk.sh
│       │   └── Toolkit/        # Android toolkit utilities (6 scripts)
│       ├── WIP/                # Work-in-progress scripts (12 scripts)
│       │   ├── Privacy-Config.sh
│       │   ├── bash-lazyrc.sh
│       │   ├── gittool.sh
│       │   ├── min-cli.sh
│       │   ├── nvidia.sh
│       │   ├── printer.sh
│       │   └── (others)
│       └── shell-tools/        # Shell utility scripts (15 scripts)
│           ├── minify.sh
│           ├── vscodium-patch.sh
│           ├── imageoptim.sh
│           ├── inifmt.sh
│           ├── vnfetch.sh
│           ├── flagscii.sh
│           ├── optimal-mtu.sh
│           ├── pachelp.sh
│           ├── template.sh
│           └── dietpi/         # DietPi-specific tools (2 scripts)
├── RaspberryPi/                # Raspberry Pi specific scripts (17 scripts)
│   ├── update.sh               # Pi system updates (100 lines)
│   ├── PiClean.sh              # Pi cleanup utilities (136 lines)
│   ├── raspi-f2fs.sh           # F2FS filesystem conversion (1,045 lines)
│   ├── forward.sh              # Port forwarding utilities (24 lines)
│   ├── Scripts/                # Pi automation scripts (13 scripts)
│   │   ├── Setup.sh            # Comprehensive Pi setup (14,768 lines)
│   │   ├── apkg.sh             # APT package manager wrapper (15,880 lines)
│   │   ├── pi-minify.sh        # System minimization + privacy (15,399 lines)
│   │   ├── blocklist.sh        # Adblock list management (6,581 lines)
│   │   ├── docker.sh           # Docker configuration (1,545 lines)
│   │   ├── Docker-clean.sh     # Docker cleanup (4,261 lines)
│   │   ├── Fix.sh              # Pi system fixes (3,908 lines)
│   │   ├── Housekeep.sh        # System housekeeping (818 lines)
│   │   ├── Kbuild.sh           # Kernel build automation (4,200 lines)
│   │   ├── copyparty.sh        # CopyParty setup (1,333 lines)
│   │   ├── podman.sh           # Podman container management (2,663 lines)
│   │   ├── sqlite-tune.sh      # SQLite optimization (4,024 lines)
│   │   └── Nextcloud/          # Nextcloud server setup (1 script)
│   ├── docs/                   # Pi documentation
│   │   ├── TODO.md
│   │   └── raspi-kernel-patches.md
│   └── dots/                   # Configuration files (apt.conf, apt-fast.conf)
├── Scripts/                    # General cross-platform scripts (2 scripts)
│   ├── Debloat.sh              # Cross-distro debloating (81 lines)
│   └── media-opt.sh            # Media file optimization (418 lines)
├── Linux-Settings/             # System configuration references
├── CLAUDE.MD                   # AI assistant instructions (this file)
├── GEMINI.MD                   # Gemini AI instructions (6,119 bytes)
├── USEFUL.MD                   # Curated resources (1,971 bytes)
├── Shell-book.md               # Bash scripting reference (14,428 bytes)
├── Searchxng.md                # SearXNG privacy search engine reference
├── todo.md                     # Project task tracking
└── README.md                   # Quick-start guide with curl-able commands
```

## Key Files & Components

### Critical Scripts (curl-able from README.md)
- **Cachyos/Updates.sh** - System update automation with package manager detection
- **Cachyos/Clean.sh** - System cleanup with smart cache management
- **Cachyos/Rank.sh** - Mirror ranking with parallel testing
- **Cachyos/archmaint.sh** (1,153 lines) - Comprehensive maintenance suite
- **Cachyos/Scripts/Install.sh** (17,593 lines) - Automated package installation (largest)
- **Cachyos/Scripts/AutoSetup.sh** (7,892 lines) - System configuration automation
- **Cachyos/Scripts/bleachbit.sh** - BleachBit extra cleaners installation
- **RaspberryPi/raspi-f2fs.sh** (1,045 lines) - F2FS conversion utility
- **RaspberryPi/Scripts/pi-minify.sh** (15,399 lines) - Debian minimization + privacy hardening

### Script Architecture (Self-Contained)
**IMPORTANT**: The repository previously used a centralized library system (`lib/common.sh`) but this was **removed** in commit 59a8613. All scripts are now **self-contained** with inlined utility functions.

**Standard Script Structure** (from Shell-book.md):
```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C LANGUAGE=C

# Color definitions (inlined in each script)
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Utility functions (inlined in each script)
has() { command -v "$1" &>/dev/null; }
log() { printf '%b\n' "$*"; }
die() { printf '%b\n' "${RED}Error:${DEF} $*" >&2; exit 1; }
```

**Pattern**: Each script includes its own complete set of:
- Color/formatting variable definitions
- Helper functions (`has`, `log`, `warn`, `die`, `confirm`)
- Package manager detection logic
- Environment variable exports

### Configuration Files
- **.editorconfig** (264 lines) - Universal formatting (shfmt, 2-space indent, bash variant detection)
- **.shellcheckrc** - Linting rules (enable=all, 16 specific exclusions, source-path=SCRIPTDIR)
- **.gitattributes** (2,381 bytes) - Git file handling
- **.gitignore** (2,160 bytes) - Security files, build artifacts, editor configs

### Package Manifests
- **Cachyos/packages-repo.txt** - Repository packages (178 packages)
  - CachyOS-specific: cachyos-settings, cachyos-hooks, cachyos-mirrorlist, cachyos-rate-mirrors
  - Toolchain: cargo-c, cargo-cache, sccache, llvm-bolt, rust-src
  - Modern CLI: bat, dust, eza, fd, btop, glances, hyperfine
  - Gaming: prismlauncher, proton-ge-custom, protonplus
- **Cachyos/packages-aur.txt** - AUR packages (11 packages)
  - aria2-unlimited, rust-parallel, uutils variants, ssh3

### Documentation Structure
- **README.md** - Quick-start with curl commands
- **CLAUDE.MD** - AI assistant development guide (this file)
- **Shell-book.md** (14,428 bytes) - Bash reference, templates, snippets
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

### Standard Boilerplate (Self-Contained Scripts)
Since the library consolidation was removed, each script includes its own:
```bash
# Common pattern across scripts:
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C LANGUAGE=C

# Inlined helper functions
has() { command -v "$1" &>/dev/null; }
log() { printf '%b\n' "$*"; }
die() { log "${RED}Error:${DEF} $*" >&2; exit 1; }
confirm() {
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}
```

## Code Patterns

### Package Management
- **Detection Chain**: `paru` → `yay` → `pacman` (Arch-based) | `apt`/`nala` (Debian-based)
- **Privilege Escalation**: `sudo-rs` → `sudo` → `doas` (detected at runtime)
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
- **SC1072/SC1073/SC1078/SC1079/SC1083**: Parse errors in specific contexts
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

**Recent Commit Pattern** (November 2025):
- Script cleanup and consolidation (deleted: adbclean2.sh, uu-sym.sh, shizuku_merge.sh, buildkernel.sh, hypershell.sh)
- RaspberryPi folder restructuring (commit: 132d4ae)
- Privacy script consolidation (merged privacy-script.sh into pi-minify.sh)
- Bash standardization (commit: 879d901)
- Documentation cleanup (deleted: Compiler.txt, Kernel.txt, Sched-ext.txt)
- Single-purpose, atomic changes

### Code Quality Standards
- Single responsibility per function/module
- Loose coupling via interfaces
- Early returns for clarity
- Avoid premature abstraction
- Eliminate duplication (inline common patterns, reference Shell-book.md)
- Explicit dependencies, clear intent
- Small, focused functions (<50 lines preferred)

### Prohibited Patterns
❌ Hardcoded values (use constants/config/environment)
❌ Repetitive code blocks (create functions or reference templates)
❌ Duplicated error handling (unify patterns)
❌ Replicated logic (inline or abstract to reusable pattern)
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
4. Update Shell-book.md if creating new reusable patterns
5. Verify no sensitive data committed (.env, tokens, keys)
6. Single logical change per commit

### Deployment Method
Scripts are curl-able from GitHub main branch:
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/path/to/script.sh | bash
```

## Build Optimization & Toolchain

### Compiler Flags
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
Available specialized agents (see `.github/agents/`):
- **bash-architect**: Script design & architecture
- **performance-engineer**: Profiling & optimization
- **config-specialist**: Configuration management
- **security-specialist**: Security audit & hardening
- **documentation-expert**: Technical writing
- **code-janitor**: Code cleanup & refactoring

Invoke: `@agent-name [task]`

## Chat Modes
Available modes (see `.github/chatmodes/`):
- `Thinking-Beast-Mode`: Deep reasoning mode
- `critical-thinking`: Analytical problem solving
- `janitor`: Code cleanup and maintenance
- `prompt-engineer`: Prompt optimization
- `rust-gpt-4.1-beast-mode`: Rust development
- `software-engineer-agent-v1`: General engineering

Activate: `/mode [mode-name]`

## Prompt Templates
Common templates (see `.github/prompts/`):
- `bash-script`: Generate bash scripts
- `boost`: Performance enhancement
- `copilot-instructions-blueprint-generator`: Create copilot configs
- `create-agentsmd`: Agent configuration generation
- `create-llms`: LLM instruction generation
- `create-readme`: Documentation generation
- `editorconfig`: EditorConfig generation
- `review-and-refactor`: Code quality review

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
- Privacy configuration scripts (pi-minify.sh includes privacy hardening)
- Debloating utilities (Debloat.sh)
- Pi-hole ad blocking (RaspberryPi/Scripts/)

### Secure Coding Practices
- Quote all variables unless word splitting intended
- Validate user input before execution
- Use `--` to separate options from arguments
- Avoid `eval` except when absolutely necessary
- Set appropriate file permissions (644 for data, 755 for scripts)
- Never log sensitive information

## Recent Repository Changes

### November 2025 Refactoring
**Major Changes**:
- **Script consolidation**: Merged privacy-script.sh into pi-minify.sh (commit: 5243dc2)
- **RaspberryPi reorganization**: Refactored folder structure (commit: 132d4ae)
- **Bash standardization**: Applied bashisms across all scripts (commit: 879d901)
- **Documentation cleanup**: Deleted Compiler.txt, Kernel.txt, Sched-ext.txt
- **WIP cleanup**: Removed deprecated scripts (adbclean2, uu-sym, shizuku_merge, buildkernel, hypershell)
- **Script relocation**: Moved rustbuild.sh from WIP to Rust/ directory

### Architectural Changes
- **Library consolidation removed** (commit: 59a8613): Deleted lib/common.sh
- **Self-contained scripts**: All utility functions now inlined
- **Privilege escalation refactoring** (commit: 94205f3): Replaced functions with direct sudo
- **Comprehensive linting** (commit: c7fa5d2): Applied formatting across all file types

### Script Count Evolution
- **Previous**: ~45 actively maintained scripts (as of Nov 18)
- **Current**: 73 shell scripts (as of Nov 22)
  - Cachyos/: 54 scripts (74%)
  - RaspberryPi/: 17 scripts (23%)
  - Scripts/: 2 scripts (3%)

---

**Last Updated**: 2025-11-22 (commit: 83af6fe - Delete Linux-Settings/Compiler.txt)
**Maintainer**: Ven0m0
**Contributors**: copilot-swe-agent[bot], Claude

*Optimized for Claude's context window and reasoning capabilities*
