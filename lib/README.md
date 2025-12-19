# Shared Library Functions

This directory contains shared utility functions to reduce code duplication across scripts.

## Usage

Source the common library at the beginning of your script:

```bash
#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || source "${SCRIPT_DIR}/lib/common.sh" || exit 1

# Your script code here
main() {
  has curl || die "curl is required"
  log "Starting process..."
  # ...
}

main "$@"
```

## Available Functions

### Command Checking

- `has <command>` - Check if a command exists in PATH

### Output Functions

- `xecho <message>` - Print formatted message (supports ANSI codes)
- `log <message>` - Print info message (green arrow)
- `warn <message>` - Print warning message (yellow warning symbol)
- `err <message>` - Print error message (red X)
- `die <message> [exit_code]` - Print error and exit (default code: 1)
- `dbg <message>` - Print debug message (only if DEBUG=1)

### Interactive Functions

- `confirm [prompt]` - Ask for y/N confirmation

### Utility Functions

- `find_with_fallback <type> <pattern> <path>` - Use fd/fdfind/find automatically
- `get_user_home` - Get user home directory (respects SUDO_USER)
- `write_sys <value> <path>` - Write to sysfs/procfs with sudo
- `write_sys_many <value> <path1> [path2...]` - Write to multiple sysfs paths
- `run_cmd <command> [args...]` - Run command with dry-run support (honors DRY_RUN=1)

### Color Variables

All color codes are pre-defined and exported:

- `BLK`, `RED`, `GRN`, `YLW`, `BLU`, `MGN`, `CYN`, `WHT`
- `LBLU`, `PNK`, `BWHT`, `DEF`, `BLD`

## Benefits

- **Consistency**: Standardized function signatures and behavior
- **Maintainability**: Single source of truth for common operations
- **Reduced Duplication**: Eliminates 200+ lines of duplicated code
- **Performance**: Functions are optimized for minimal overhead
- **Safety**: Functions include proper error handling and quoting

## Migration Guide

When refactoring existing scripts:

1. Add the source line after the shebang and set commands
2. Remove local definitions of `has()`, `xecho()`, `log()`, `warn()`, `err()`, `die()`
3. Remove color variable definitions if using standard colors
4. Update function calls to match library signatures if needed
5. Test the script to ensure it works correctly
