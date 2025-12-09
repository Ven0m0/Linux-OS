# Linux-OS Shared Libraries

This directory contains shared utility functions and common code extracted from across the Linux-OS repository to reduce duplication and improve maintainability.

## Libraries

### common.sh

Core helper functions used across all scripts.

**Functions:**

- `init_shell()` - Initialize shell with strict error handling and sane defaults
- `has()` - Check if command exists in PATH
- `xecho()` - Printf wrapper for consistent output formatting
- `log()`, `warn()`, `err()`, `die()` - Logging functions with colored output
- `dbg()`, `ok()`, `info()` - Additional logging utilities
- `confirm()` - User confirmation prompts
- `on_err()`, `cleanup()`, `setup_traps()` - Error handling helpers
- `detect_priv_cmd()`, `run_priv()` - Privilege escalation detection and execution
- `detect_fd()`, `detect_grep()`, `detect_download()`, `detect_json()` - Tool detection with fallbacks
- `find0()` - NUL-safe file finder
- `download_file()` - Download file with automatic tool selection
- `is_wayland()`, `is_arch()`, `is_debian()`, `is_pi()`, `detect_distro()` - System detection
- `load_array_from_file()` - Load filtered array from file
- `wait_for_process()`, `kill_process()` - Process management

**Colors:**
Exports standard ANSI colors and trans flag palette (LBLU, PNK, BWHT, etc.)

**Usage:**

```bash
source "${BASH_SOURCE%/*}/../lib/common.sh"
init_shell
log "Starting operation..."
```

### browser-utils.sh

Browser profile discovery and SQLite database optimization functions.

**Functions:**

- `vacuum_sqlite()` - Vacuum single SQLite database and return bytes saved
- `clean_sqlite_dbs()` - Clean all SQLite databases in current directory
- `ensure_not_running()` - Wait for processes to exit, kill if timeout
- `foxdir()` - Find default Firefox-family profile directory
- `mozilla_profiles()` - List all Mozilla profiles in a base directory
- `chrome_profiles()` - List Chrome/Chromium profile directories
- `chrome_roots_for()` - List Chrome-based browser root directories
- `mozilla_bases_for()` - List Mozilla-based browser base directories
- `mail_bases_for()` - List Thunderbird/mail client base directories

**Usage:**

```bash
source "${BASH_SOURCE%/*}/../lib/browser-utils.sh"

# Clean Firefox profiles
while read -r base; do
  while read -r prof; do
    (cd "$prof" && clean_sqlite_dbs)
  done < <(mozilla_profiles "$base")
done < <(mozilla_bases_for "$USER")
```

### pkg-utils.sh

Package manager detection and operations with caching.

**Functions:**

- `detect_pkg_manager()` - Detect and cache package manager (paru/yay/pacman/apt)
- `get_pkg_manager()` - Get cached package manager name
- `get_aur_opts()` - Get cached AUR helper options
- `get_aur_install_flags()` - Get standard AUR helper installation flags
- `pkg_install()` - Install packages using detected package manager
- `pkg_remove()` - Remove packages using detected package manager
- `pkg_installed()` - Check if package is installed
- `pkg_update()` - Update package database
- `pkg_upgrade()` - Upgrade all packages
- `pkg_clean()` - Clean package cache
- `pkg_autoremove()` - Remove orphaned packages
- `setup_build_env()` - Setup optimized build environment for native compilation

**Usage:**

```bash
source "${BASH_SOURCE%/*}/../lib/pkg-utils.sh"

# Install packages
pkg_install package1 package2 package3

# Setup build environment
setup_build_env

# Clean package cache
pkg_clean
```

## Design Principles

1. **Single Source of Truth:** Update helper function once, affects all scripts
2. **Backward Compatibility:** Scripts can override library functions if needed
3. **No External Dependencies:** Libraries use only bash builtins and common tools
4. **Tool Detection:** Automatically detect and use best available tool (fd/find, rg/grep, etc.)
5. **Fail-Safe:** Functions return gracefully if tools are missing

## Sourcing Libraries

All libraries are designed to be sourced from scripts in subdirectories:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/browser-utils.sh"
source "$SCRIPT_DIR/../lib/pkg-utils.sh"
```

For scripts in nested directories (e.g., `Cachyos/Scripts/`):

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
```

## Refactored Scripts

The following scripts have been refactored to use these shared libraries:

- `Cachyos/clean.sh` - 460→236 lines (-49%)
- `Cachyos/archmaint.sh` - 938→772 lines (-18%)

## Future Work

Candidates for additional refactoring:

- `Cachyos/Scripts/Fix.sh` - Contains duplicated browser and package manager functions
- `RaspberryPi/Scripts/Fix.sh` - Similar duplication patterns
- `Cachyos/Updates.sh` - Could use pkg-utils functions
- `RaspberryPi/update.sh` - Could use pkg-utils functions

## Contributing

When adding new shared functions:

1. Place generic utilities in `common.sh`
2. Place browser-specific functions in `browser-utils.sh`
3. Place package management functions in `pkg-utils.sh`
4. Document the function with usage examples
5. Update this README
6. Test on both Arch and Debian systems

## Testing

Test libraries before committing:

```bash
# Syntax validation
for lib in lib/*.sh; do
  bash -n "$lib" && echo "✓ $lib" || echo "✗ $lib"
done

# Source test
bash -c "source lib/common.sh && source lib/browser-utils.sh && source lib/pkg-utils.sh && echo 'All libraries loaded successfully'"
```
