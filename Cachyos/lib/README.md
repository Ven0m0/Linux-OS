# Common Library for Linux-OS Scripts

This directory contains shared functions and utilities used across multiple bash scripts in the Linux-OS repository.

## Files

- **common.sh** - Main common library providing shared functionality

## Usage

To use the common library in your script:

```bash
#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh" || exit 1
```

## Features Provided

### Color Definitions
Trans flag color palette with exported variables:
- `BLK`, `WHT`, `BWHT` - Black, white, bright white
- `RED`, `GRN`, `YLW` - Red, green, yellow
- `BLU`, `CYN`, `LBLU` - Blue, cyan, light blue
- `MGN`, `PNK` - Magenta, pink
- `DEF`, `BLD` - Default (reset), bold

### Core Helper Functions
- `has(cmd)` - Check if command exists
- `xecho(msg)` - Echo with formatting support
- `log(msg)` - Log message to stdout
- `err(msg)` - Log error to stderr
- `die(msg)` - Print error and exit with status 1
- `confirm(msg)` - Interactive confirmation prompt

### Privilege Escalation
- `get_priv_cmd()` - Detect available privilege tool (sudo-rs, sudo, doas)
- `init_priv()` - Initialize privilege tool and return it
- `run_priv(cmd...)` - Execute command with appropriate privilege escalation

### Banner Printing
- `print_banner(banner, [title])` - Print ASCII banner with trans flag gradient
- `get_update_banner()` - Returns UPDATES ASCII art
- `get_clean_banner()` - Returns CLEANING ASCII art
- `print_named_banner(name, [title])` - Print predefined banner ("update" or "clean")

### Build Environment
- `setup_build_env()` - Setup optimized compilation environment with:
  - Rust optimization flags
  - C/C++ compiler flags
  - Linker flags
  - Parallel build settings
  - LLVM toolchain selection

### Common Cleanup Patterns
- `cleanup_pacman_lock()` - Remove pacman database lock
- `cleanup_generic()` - Generic cleanup (calls cleanup_pacman_lock)
- `setup_cleanup_trap()` - Setup standard EXIT/INT/TERM trap handlers

### System Maintenance
- `run_system_maintenance(cmd, [args...])` - Safely run maintenance commands
  - Handles: modprobed-db, hwclock, updatedb, chwd, mandb

### Disk Usage
- `capture_disk_usage(var_name)` - Capture current disk usage into named variable

### File Operations
- `find_files([args...])` - Use `fd` if available, fallback to `find`
- `find0(path, [args...])` - NUL-safe file finder using fd/fdf/find (for use with xargs -0)

### SQLite Maintenance
- `vacuum_sqlite(db_path)` - Vacuum a single SQLite database, returns bytes saved
- `clean_sqlite_dbs()` - Clean all SQLite databases in current working directory

### Process Management
- `ensure_not_running_any(prog...)` - Wait for processes to exit, kill if timeout

### Browser Profile Detection
- `foxdir(base_path)` - Find active Firefox profile directory
- `mozilla_profiles(base_path)` - List all Mozilla profiles (Firefox, LibreWolf, etc.)
- `chrome_roots_for(product)` - Get Chrome/Chromium root directories (native/flatpak/snap)
- `chrome_profiles(root)` - List Chrome profiles under a root directory

### Path Cleaning Helpers
- `clean_paths(paths...)` - Clean arrays of file/directory paths efficiently
- `clean_with_sudo(paths...)` - Clean paths with privilege escalation

### Package Manager Detection
- `detect_pkg_manager()` - Detect best available AUR helper (paru, yay) or pacman

## Benefits

- **DRY Principle**: Single source of truth for common patterns
- **Consistency**: Standardized behavior across all scripts
- **Maintainability**: Changes in one place benefit all scripts
- **Reduced Code**: Eliminates ~270+ lines of duplicated code across 6 scripts
- **Better Testing**: Common functions can be tested in isolation

## Refactored Scripts

Scripts that have been refactored to use this library:
- `Cachyos/Updates.sh`
- `Cachyos/Clean.sh`
- `Cachyos/Rank.sh`
- `Cachyos/archmaint.sh`
- `Cachyos/Scripts/Install.sh`
- `Cachyos/Scripts/Privacy-Config.sh`
- `Cachyos/Scripts/bench.sh`

## Contributing

When adding new common functionality:
1. Ensure it's genuinely reusable across multiple scripts
2. Document the function with comments
3. Add it to the appropriate section in common.sh
4. Update this README with the new function
5. Test with existing scripts that use the library
6. Consider backward compatibility with existing scripts
