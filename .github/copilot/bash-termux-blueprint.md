# Bash Scripts and Termux Environment Blueprint

## Project Overview

This repository contains a carefully curated Termux environment with production-grade Bash utilities optimized for Android environments. The codebase emphasizes performance, safety, and cross-platform compatibility while maintaining simplicity and single-file design principles.

## Priority Guidelines

When generating code for this repository:

1. **Termux-First Design**: Optimize primarily for Termux/Android, with Arch Linux and Debian as secondary targets
2. **Single-File Architecture**: Keep utilities self-contained with inline helpers rather than external libraries
3. **Performance Priority**: Favor in-memory operations, minimal external processes, and modern Rust tools when available
4. **Safety Standards**: Implement strict error handling, proper quoting, and signal trapping
5. **Cross-Platform Compatibility**: Provide graceful fallbacks and platform-specific optimizations

## Technology Stack Detection

### Primary Technologies
- **Shell**: Bash 5.x (Termux environment)
- **Configuration Shell**: Zsh with Zinit plugin manager
- **Modern CLI Tools**: fd, ripgrep (rg), bat, eza, zoxide, dust, broot
- **Traditional Fallbacks**: find, grep, sed, awk, less, ls

### Platform Detection Patterns
```bash
# Detect Termux environment
if [[ -d "/data/data/com.termux" ]]; then
  PLATFORM="termux"
  SHEBANG="#!/data/data/com.termux/files/usr/bin/env bash"
else
  PLATFORM="linux"
  SHEBANG="#!/usr/bin/env bash"
fi
```

## Code Style and Standards

### Mandatory Script Header
```bash
#!/data/data/com.termux/files/usr/bin/env bash  # For Termux scripts
# OR
#!/usr/bin/env bash  # For general Linux scripts

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C LANGUAGE=C
```

### Indentation and Formatting
- **Indentation**: 2 spaces (no tabs)
- **Line Length**: 80 characters maximum where practical
- **Function Style**: `function_name() { ... }` format
- **Variable Naming**: `CONSTANTS_UPPER`, `local_vars_lower`, `readonly` for immutable values

### Required Safety Patterns
```bash
# Signal handling
cleanup() { :; }
trap 'rc=$?; trap - EXIT; cleanup; exit "$rc"' EXIT
trap 'trap - INT; exit 130' INT
trap 'trap - TERM; exit 143' TERM

# Dependency checking with platform hints
has() { command -v -- "$1" >/dev/null 2>&1; }
_hint_arch() { printf 'pacman -S --needed %s\n' "$*"; }
_hint_deb() { printf 'sudo apt-get install -y %s\n' "$*"; }
_hint_termux() { printf 'pkg install %s\n' "$*"; }

require_deps() {
  local miss=()
  for d in "$@"; do
    has "$d" || miss+=("$d")
  done
  ((${#miss[@]}==0)) && return 0
  printf 'missing deps: %s\n' "${miss[*]}" >&2
  printf 'Termux: %s' "$(_hint_termux "${miss[*]}")" >&2
  printf 'Arch:   %s' "$(_hint_arch "${miss[*]}")" >&2
  printf 'Debian: %s' "$(_hint_deb "${miss[*]}")" >&2
  exit 127
}
```

## Architectural Patterns

### Single-File Design Philosophy
- No external library sourcing by default
- Keep helper functions inline
- Minimize startup time (<100ms target)
- Self-documenting code with usage functions

### Preferred Constructs
- **Arrays**: Use arrays and associative arrays over external processing
- **Here-strings**: `cmd <<<"$var"` instead of `echo "$var" | cmd`
- **Input Processing**: `while IFS= read -r` for robust line reading
- **Conditionals**: `[[ ... ]]` for tests instead of `[ ... ]`
- **Parameter Passing**: nameref for in/out parameters
- **Output Capture**: `ret=$(fn ...)` pattern

### Tool Preference Hierarchy
```bash
# File finding: fd > find
if has fd; then
  mapfile -t files < <(fd -t f -e sh .)
else
  mapfile -t files < <(find . -type f -name "*.sh" -print)
fi

# Text search: rg > grep
if has rg; then
  rg -n "pattern" "$file"
else
  grep -n "pattern" "$file"
fi

# File viewing: bat > less > cat
PAGER=${PAGER:-$(command -v bat || command -v less || echo cat)}
```

## Performance Optimization Patterns

### Parallel Processing
```bash
# Parallel file processing
printf '%s\0' "${files[@]}" | xargs -0 -n1 -P"$(nproc 2>/dev/null || echo 1)" process_file

# Control concurrency with -j flag
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 1)}"
```

### Memory Efficiency
- Use parameter expansion over external commands where possible
- Avoid unnecessary subshells
- Use process substitution for pipeline state preservation
- Prefer built-in operations over external tools

### I/O Optimization
```bash
# Fast file reading for small files
fcat() { printf '%s\n' "$(<"$1")"; }

# Efficient basename/dirname
bname() {
  local t=${1%${1##*[!/]}}
  t=${t##*/}
  [[ $2 && $t == *"$2" ]] && t=${t%$2}
  printf '%s\n' "${t:-/}"
}
```

## Error Handling Standards

### Defensive Programming
- Quote all variables: `"$var"` not `$var`
- Never parse `ls` output
- Avoid untrusted `eval`
- Use `|| true` for non-critical failures that should not abort

### File Operations
```bash
# Atomic writes
write_temp_then_move() {
  local content=$1 target=$2
  local temp_file
  temp_file=$(mktemp -p "${TMPDIR:-/tmp}")
  printf '%s\n' "$content" > "$temp_file"
  mv "$temp_file" "$target"
}

# Backup before destructive operations
backup_file() {
  local file=$1
  [[ -f "$file" ]] && cp "$file" "${file}.bak.$(date +%Y%m%d-%H%M%S)"
}
```

## Configuration Management

### Command Line Arguments
```bash
# Standard getopts pattern
QUIET=0 VERBOSE=0 DRYRUN=0 ASSUME_YES=0
JOBS="${JOBS:-0}" OUT=""

parse_args() {
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
}
```

### Environment Variable Patterns
- Prefer environment variable overrides: `FOO=1 script -o out`
- Use `${VAR:-default}` for defaults
- Export only when necessary for child processes

## Testing and Quality Assurance

### Linting Requirements
- **shellcheck**: Mandatory static analysis
- **shfmt**: Formatting with `-i 2 -ci -sr` flags
- **Test Framework**: bats-core for functional tests (when scripts stabilize)

### Validation Patterns
```bash
# Input validation
validate_file() {
  local file=$1
  [[ -f "$file" ]] || die "File not found: $file"
  [[ -r "$file" ]] || die "File not readable: $file"
}

# User confirmation
confirm() {
  local msg=${1:-Proceed?} ans
  (( ASSUME_YES == 1 )) && return 0
  printf '%s [y/N]: ' "$msg" >&2
  IFS= read -r ans || true
  [[ "$ans" == [Yy]* ]]
}
```

## Termux-Specific Patterns

### Path Handling
```bash
# Termux-aware path resolution
TERMUX_PREFIX="/data/data/com.termux/files/usr"
if [[ -d "$TERMUX_PREFIX" ]]; then
  PATH="$TERMUX_PREFIX/bin:$PATH"
fi
```

### Package Management
```bash
# Cross-platform package installation hints
install_hint() {
  local pkg=$1
  if [[ -d "/data/data/com.termux" ]]; then
    echo "pkg install $pkg"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman -S --needed $pkg"
  elif command -v apt >/dev/null 2>&1; then
    echo "sudo apt-get install -y $pkg"
  fi
}
```

### Android Integration
```bash
# Termux API integration patterns
if has termux-clipboard-set; then
  copy_to_clipboard() { termux-clipboard-set < "$1"; }
else
  copy_to_clipboard() { echo "Clipboard not available"; }
fi
```

## Documentation Standards

### Usage Function Template
```bash
usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] [-q] [-v] [-n] [-y] [-j n] [-o path] [args...]

Description: Brief description of what this script does

Options:
  -h        Show this help message
  -q        Quiet mode (suppress output)
  -v        Verbose mode (enable debug output)
  -n        Dry-run mode (show what would be done)
  -y        Assume yes for all prompts
  -j n      Number of parallel jobs (default: nproc)
  -o path   Output path/file

Examples:
  $(basename "$0") -v file.txt
  $(basename "$0") -j 4 -o output.txt *.sh

Environment Variables:
  DEBUG=1   Enable debug output
  JOBS=n    Set number of parallel jobs
EOF
}
```

### Inline Documentation
- Minimal but sufficient comments
- Document non-obvious behavior
- Include examples for complex functions
- Use self-documenting variable and function names

## File Organization

### Repository Structure
```
/
├── .github/
│   ├── copilot/               # Copilot instructions
│   └── prompts/               # AI prompt templates
├── bin/                       # Executable scripts
│   ├── *.sh                   # Single-file utilities
│   └── rxfetch                # System info display
├── .config/                   # Configuration files
│   └── bash/                  # Bash-specific configs
├── .termux/                   # Termux-specific settings
└── setup.sh                  # Environment setup script
```

### Script Naming Conventions
- Executable scripts: `script-name.sh` in `bin/`
- Library functions: `_helper-functions.sh` (if needed)
- Configuration: `.config/bash/script-name.conf`

## Integration Patterns

### Zsh Configuration Integration
- Scripts should work in both Bash and when called from Zsh
- Respect Zsh environment variables when present
- Maintain compatibility with Zinit plugin system

### Modern Tool Integration
```bash
# Tool detection and configuration
setup_modern_tools() {
  # File finding
  if has fd; then
    alias find_files='fd -t f'
  else
    alias find_files='find . -type f'
  fi

  # Text search
  if has rg; then
    export GREP_TOOL='rg'
  else
    export GREP_TOOL='grep -r'
  fi

  # File viewing
  if has bat; then
    export PAGER='bat'
    export BAT_THEME="Dracula"
  fi
}
```

## Security Considerations

### Safe Scripting Practices
- Always quote variables in potentially unsafe contexts
- Validate user input before processing
- Use `mktemp` for temporary files
- Avoid `eval` with untrusted input
- Set restrictive permissions on sensitive files

### Privilege Handling
```bash
# Sudo detection and caching
check_sudo() {
  local sudo_cmd
  if command -v sudo-rs >/dev/null 2>&1; then
    sudo_cmd="sudo-rs"
  elif command -v sudo >/dev/null 2>&1; then
    sudo_cmd="sudo"
  elif command -v doas >/dev/null 2>&1; then
    sudo_cmd="doas"
  else
    die "No privilege escalation tool found"
  fi
  export SUDO_CMD="$sudo_cmd"
}
```

## Performance Benchmarks

### Startup Time Targets
- Simple utilities: <50ms
- Complex utilities: <100ms
- Setup scripts: <500ms

### Memory Usage Guidelines
- Avoid loading large files into memory
- Use streaming where possible
- Prefer external tools for heavy processing

## Deployment and Distribution

### Installation Pattern
- Single-command installation via curl
- Dependency verification before execution
- Graceful fallbacks for missing tools
- Cross-platform compatibility checks

### Update Mechanism
```bash
# Self-updating pattern
update_script() {
  local script_url="https://raw.githubusercontent.com/Ven0m0/dot-termux/main/bin/$(basename "$0")"
  local backup_file="${0}.bak.$(date +%Y%m%d-%H%M%S)"

  if curl -sfL "$script_url" -o "$backup_file"; then
    mv "$backup_file" "$0"
    chmod +x "$0"
    echo "Updated successfully"
  else
    rm -f "$backup_file"
    die "Update failed"
  fi
}
```

## Project-Specific Guidelines

### Image and Media Processing
- Support common formats: JPEG, PNG, WebP, AVIF, GIF, SVG
- Parallel processing for batch operations
- Quality control with configurable parameters
- Progress reporting for long operations

### Android/ADB Integration
- Safe device detection and authorization checks
- Graceful handling of disconnections
- Progress reporting for large data transfers
- Temporary file cleanup after operations

### Dotfiles Management
- Atomic symlink creation with backups
- Cross-platform path resolution
- Dependency verification before installation
- Rollback capability for failed installations

## Maintenance Guidelines

### Code Reviews
- Verify shellcheck compliance
- Test on multiple platforms (Termux, Arch, Debian)
- Validate performance targets
- Ensure proper error handling

### Regular Updates
- Keep tool preference lists current
- Update installation hints for new platforms
- Refresh dependency versions
- Review and update documentation

---

*This blueprint should be consulted before creating or modifying any Bash scripts in this repository. It represents the accumulated best practices and patterns observed in the existing codebase.*

