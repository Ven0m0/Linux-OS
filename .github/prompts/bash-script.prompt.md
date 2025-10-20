# Professional Bash Script Development Guide

## Overview
This guide establishes standards for production-grade Bash scripts in enterprise environments.

## Technical Requirements
- Bash 4.0+ (required for associative arrays and mapfile)
- POSIX compliance for core functionality
- Zero ShellCheck warnings/errors (strict mode)
- Verified compatibility: RHEL 7+, Ubuntu 20.04+, Debian 10+

## Script Structure
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Metadata
VERSION="1.0.0"
SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(mktemp -d)"

# Error handling
trap 'cleanup' EXIT INT TERM
cleanup() { rm -rf "${WORKDIR}"; }
die() { echo "[ERROR] ${1}" >&2; exit "${2:-1}"; }
log() { echo "[$(date -Iseconds)] ${1}"; }

# Dependencies
REQUIRED_TOOLS=(curl git rsync)
for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} required" 1
done
```

## Mandatory Components
1. Error Management
   - Comprehensive trap handling
   - Structured error messages
   - Non-zero exit codes for failures

2. Security
   - Input validation/sanitization
   - Secure temporary files (mktemp)
   - Explicit file permissions
   - Environment isolation
   - Protected variable scope

3. User Interface
   - --help: Usage documentation
   - --version: Version info
   - --debug: Debug output
   - --quiet: Suppress non-error output

4. Documentation
   - Purpose statement
   - Usage examples
   - Environment variables
   - Exit codes
   - Dependencies

## Testing Requirements
1. Unit tests (using bats-core)
2. Integration tests
3. ShellCheck validation
4. Distribution compatibility tests
5. Performance benchmarks

## Style Guide
1. Use shellcheck directives sparingly
2. Implement safe defaults
3. Use built-ins over external commands
4. Follow Google Shell Style Guide
5. Apply consistent formatting (shfmt)

## Performance
1. Minimize subshells
2. Use parameter expansion
3. Optimize file operations
4. Cache repeated operations
5. Use native bash arithmetic

## Validation
1. Run shellcheck --severity=style
2. Execute full test suite
3. Verify POSIX compliance
4. Test error conditions
5. Benchmark critical paths

Documentation: [Bash Manual](https://www.gnu.org/software/bash/manual/), [Shell Style Guide](https://google.github.io/styleguide/shellguide.html), [ShellCheck](https://www.shellcheck.net/wiki/)
