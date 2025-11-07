# Claude Instructions: Linux-OS

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

### Code Patterns

#### Package Management
- **Detection Chain**: `paru` → `yay` → `pacman` (Arch-based) | `apt`/`dpkg` (Debian-based)
- **Pre-Installation Checks**: `pacman -Q pkg` | `flatpak list` | `cargo install --list`
- **Distro-Specific Hints**: Include installation commands for both ecosystems
  - Example: `(Arch: pacman -S tool)` `(Debian: apt-get install -y tool)`

#### Data Handling & Performance
- **Array Population**: `mapfile -t arr < <(command)` — avoids subshell performance penalties
- **Prohibitions**: Never parse `ls` output
- **Associative Arrays**: `declare -A cfg=([dry_run]=0 [debug]=0 [verbose]=0)`
- **Modern Tool Preferences**:
  - File finding: `fd` → `find`
  - Text search: `rg` → `grep`
  - File viewing: `bat` → `cat`
  - Text substitution: `sd` → `sed`
  - Download: `aria2` → `curl` → `wget` (no aria2 for piped output)
  - JSON processing: `jaq` → `jq`
  - Fuzzy selection: `sk` → `fzf`
- **Optimization Focus**: Batch operations, minimize subprocess spawning

#### Interactive Mode
- **Fuzzy Finder Integration**: Use fzf for path selection when args missing
- **Fallback Pattern**: `has fd && fd -t f | fzf || find . -type f | fzf`
- **AUR Helper Flags**: `--needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --batchinstall`

#### Network Operations
- **Standard Flags**: `curl -fsL --http2`
- **Documentation**: Update README curl snippets when modifying entrypoints

## Tooling Standards

### Code Quality Pipeline
```bash
shfmt -i 2 -ln bash -bn -s file.sh && \
shellcheck -f diff file.sh | patch -Np1 && \
shellharden --replace file.sh
```

### Tool Fallback Chains
- File operations: `fdf` → `fd` → `find` (avoid fd -exec, use find for exec)
- Downloads: `aria2` → `curl` → `wget2` → `wget` (no aria2 if piping)
- Parallelization: `rust-parallel` → `parallel` → `xargs`

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

### Code Quality Standards
- Single responsibility per function/module
- Loose coupling via interfaces
- Early returns for clarity
- Avoid premature abstraction
- Eliminate duplication immediately
- Explicit dependencies, clear intent
- Small, focused functions

### Prohibited Patterns
❌ Hardcoded values (use constants/config/environment)
❌ Repetitive code blocks (create functions)
❌ Duplicated error handling (unify patterns)
❌ Replicated logic (abstract appropriately)

## Agent System
Available specialized agents (see `claude-agents.yml`):
- **bash-architect**: Script design & architecture
- **performance-engineer**: Profiling & optimization
- **config-specialist**: Configuration management
- **security-specialist**: Security audit & hardening
- **documentation-expert**: Technical writing

Invoke: `@agent-name [task]`

## Chat Modes
Available modes (see `chat-modes.yml`):
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
Common templates (see `prompt-templates.yml`):
- `optimize-script`: Performance optimization
- `add-error-handling`: Error handling patterns
- `make-distro-agnostic`: Multi-distro support
- `add-interactive-mode`: fzf integration
- `security-audit`: Security review
- `write-tests`: Test generation
- `generate-readme`: Documentation
- `modernize-tools`: Tool upgrades
- `add-dry-run`: Safe preview mode
- `parallel-processing`: Concurrent execution

Use: `/template [template-name]`

---

*Optimized for Claude's context window and reasoning capabilities*
