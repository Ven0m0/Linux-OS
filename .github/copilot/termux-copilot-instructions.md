# GitHub Copilot Instructions for Termux Environment

## Priority Guidelines

When generating code for this repository:

1. **Termux Optimization**: Always use Termux-specific patterns and paths
2. **Single-File Design**: Create self-contained scripts with inline helpers
3. **Modern Tool Preference**: Use Rust tools (fd, rg, bat) with fallbacks
4. **Strict Safety**: Implement proper error handling and signal trapping
5. **Performance Focus**: Optimize for speed and minimal resource usage

## Technology Version Detection

### Shell Environment
- **Primary Shell**: Bash 5.x in Termux environment
- **Configuration Shell**: Zsh with Zinit plugin manager
- **Shebang Pattern**: `#!/data/data/com.termux/files/usr/bin/env bash` for Termux scripts

### Tool Ecosystem
**Modern Tools (Preferred)**:
- File finding: `fd` over `find`
- Text search: `ripgrep` (rg) over `grep`
- File viewing: `bat` over `less`
- Directory listing: `eza` over `ls`
- Navigation: `zoxide` over `cd`

**Package Managers**:
- Termux: `pkg install package-name`
- Arch Linux: `pacman -S --needed package-name`
- Debian/Ubuntu: `sudo apt-get install -y package-name`

## Codebase Patterns

### Mandatory Script Structure
```bash
#!/data/data/com.termux/files/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C LANGUAGE=C

# Script variables
readonly SELF="${BASH_SOURCE[0]}"
readonly SCRIPT_DIR="${SELF%/*}"

# Standard functions (copy from existing scripts)
has() { command -v -- "$1" >/dev/null 2>&1; }
die() { printf '%s\n' "$*" >&2; exit 1; }
cleanup() { :; }

# Signal handling
trap 'rc=$?; trap - EXIT; cleanup; exit "$rc"' EXIT
trap 'trap - INT; exit 130' INT
trap 'trap - TERM; exit 143' TERM
```

### Error Handling Patterns
- Always quote variables: `"$variable"` not `$variable`
- Use `set -euo pipefail` for strict error handling
- Implement signal trapping for clean exits
- Provide installation hints for missing dependencies
- Use `|| true` for non-critical operations that may fail

### Performance Patterns
- Prefer parameter expansion over external commands
- Use arrays instead of repeated external tool calls
- Implement parallel processing with `xargs -P`
- Cache expensive operations in variables
- Use process substitution to avoid subshells

### Dependency Checking Pattern
```bash
require_deps() {
  local miss=()
  for d in "$@"; do
    has "$d" || miss+=("$d")
  done
  ((${#miss[@]}==0)) && return 0
  printf 'missing deps: %s\n' "${miss[*]}" >&2
  printf 'Termux: pkg install %s\n' "${miss[*]}" >&2
  printf 'Arch:   pacman -S --needed %s\n' "${miss[*]}" >&2
  printf 'Debian: sudo apt-get install -y %s\n' "${miss[*]}" >&2
  exit 127
}
```

## File Organization Standards

### Script Location and Naming
- Executable utilities: `bin/script-name.sh`
- Configuration files: `.config/bash/` or appropriate XDG directory
- Termux-specific: `.termux/termux.properties`

### Configuration Management
- Use environment variables for configuration
- Support command-line flag overrides
- Provide sensible defaults
- Include `--help` and usage functions

## Code Quality Standards

### Maintainability
- Write self-documenting code with clear function names
- Keep functions focused on single responsibilities
- Use consistent naming conventions throughout
- Limit line length to 80 characters where practical
- Include brief but sufficient comments for complex logic

### Performance
- Use built-in Bash features over external commands
- Implement parallel processing for batch operations
- Cache results of expensive operations
- Prefer streaming over loading entire files into memory
- Target <100ms startup time for utilities

### Security
- Validate all user input before processing
- Use `mktemp` for temporary files
- Never use `eval` with untrusted input
- Quote all variable expansions properly
- Set appropriate file permissions

## Testing Approach

### Validation Patterns
- Use `shellcheck` for static analysis
- Format with `shfmt -i 2 -ci -sr`
- Test on Termux, Arch, and Debian where possible
- Verify dependency checking works correctly
- Test error conditions and edge cases

### Manual Testing
- Verify scripts work without optional dependencies
- Test with both modern tools and fallbacks
- Confirm proper error messages and exit codes
- Validate help text and usage examples

## Platform-Specific Guidelines

### Termux Optimizations
- Use Termux API when available (`termux-*` commands)
- Handle Android-specific paths correctly
- Support Termux storage access patterns
- Integrate with Android clipboard and sharing

### Cross-Platform Compatibility
- Detect platform and adjust behavior accordingly
- Provide appropriate package installation hints
- Handle different versions of common tools
- Use portable command-line options

## Documentation Requirements

### Usage Function Template
```bash
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [ARGUMENTS]

DESCRIPTION
  Brief description of script purpose and functionality

OPTIONS
  -h, --help     Show this help message
  -q, --quiet    Suppress output
  -v, --verbose  Enable verbose output
  -n, --dry-run  Show what would be done
  -y, --yes      Assume yes for prompts

EXAMPLES
  $(basename "$0") file.txt
  $(basename "$0") -v --dry-run *.sh

EOF
}
```

### Inline Documentation
- Document complex algorithms or logic
- Explain platform-specific workarounds
- Include examples for non-obvious usage
- Reference external documentation when relevant

## Integration Guidelines

### Zsh Environment Compatibility
- Scripts should work when called from Zsh
- Respect existing environment variables
- Don't conflict with Zinit plugin system
- Maintain compatibility with existing aliases

### Tool Integration Patterns
```bash
# Prefer modern tools with fallbacks
if has fd; then
  find_files() { fd "$@"; }
elif has find; then
  find_files() { find . -name "$@" -type f; }
else
  die "No file finding tool available"
fi
```

## Project-Specific Guidance

### Image Processing Scripts
- Support JPEG, PNG, WebP, AVIF, GIF, SVG formats
- Use parallel processing for batch operations
- Provide quality control parameters
- Include progress reporting for long operations
- Handle both lossy and lossless optimization

### Android/ADB Integration
- Verify device connection before operations
- Handle authorization prompts gracefully
- Provide clear error messages for common failures
- Support both device and emulator environments
- Clean up temporary files after operations

### Dotfiles Management
- Create atomic symlinks with backup capability
- Verify source files exist before linking
- Support both relative and absolute paths
- Provide rollback functionality
- Handle permission issues gracefully

## General Best Practices

- Analyze existing scripts for patterns before creating new ones
- Follow the same error handling approach as similar scripts
- Use consistent variable naming with existing codebase
- Match the level of verbosity in help text and comments
- Prioritize consistency with existing code over external conventions
- Test thoroughly on Termux before considering the script complete

When in doubt, examine the existing scripts in `bin/` directory for examples of proper implementation patterns, especially `img.sh`, `media.sh`, and `revanced-helper.sh` which demonstrate the preferred architecture and coding style.

