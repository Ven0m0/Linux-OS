# Linux-OS Bash Libraries Documentation

## Overview

The Linux-OS repository uses a modular library system to eliminate code duplication and improve maintainability. All Bash scripts should source the appropriate libraries instead of duplicating common functions.

## Library Structure

```
lib/
├── base.sh         # Core functions used by all scripts
├── arch.sh         # Arch Linux specific functions
├── debian.sh       # Debian/Raspbian specific functions
├── ui.sh           # User interface (banners, menus, text processing)
└── cleaning.sh     # System cleanup functions
```

## Library Descriptions

### lib/base.sh - Base Library

**Core functionality required by all scripts.**

#### Features:
- Environment setup (shell options, locale, IFS)
- Color constants (trans flag palette)
- Core helper functions (`has`, `hasname`)
- Logging functions (`log`, `info`, `ok`, `warn`, `err`, `die`, `section`)
- Confirmation prompts (`confirm`)
- Privilege escalation (`get_priv_cmd`, `init_priv`, `run_priv`, `require_root`)
- Working directory management (`get_workdir`, `init_workdir`, `get_script_dir`)
- File finding utilities (`find_files`, `find0`, `find_with_fallback`)
- Download tool detection (`get_download_tool`, `download_file`)
- Path manipulation (`bname`, `dname`, `clean_paths`, `clean_with_sudo`)
- System information (`get_nproc`, `get_disk_usage`, `capture_disk_usage`)
- Trap helpers (`setup_traps`)

#### Usage:
```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
```

#### Key Functions:

**Command Detection:**
```bash
has git || die "git is required"
```

**Logging:**
```bash
info "Starting process..."
ok "Process completed successfully"
warn "This might take a while"
err "An error occurred"
die "Fatal error, exiting"
```

**Privilege Escalation:**
```bash
# Initialize privilege tool (sudo/doas)
PRIV_CMD=$(init_priv)

# Run command with appropriate privileges
run_priv systemctl restart service
```

**Working Directory:**
```bash
# Initialize and change to script directory
init_workdir

# Or get directory without changing
WORKDIR=$(get_workdir)
```

---

### lib/arch.sh - Arch Linux Library

**Platform-specific functions for Arch Linux / CachyOS.**

Requires: `lib/base.sh`

#### Features:
- Package manager detection with caching (pacman/paru/yay)
- Build environment setup (compiler flags, parallel builds)
- System maintenance functions
- SQLite optimization
- Process management
- Browser profile detection (Firefox, Chromium families)
- Cargo cache management

#### Usage:
```bash
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/arch.sh" || exit 1
```

#### Key Functions:

**Package Manager:**
```bash
# Get package manager name
pkgmgr=$(get_pkg_manager)  # Returns: paru, yay, or pacman

# Get AUR helper options
mapfile -t aur_opts < <(get_aur_opts)
```

**Build Environment:**
```bash
# Setup optimized compiler flags and parallel builds
setup_build_env
```

**SQLite Optimization:**
```bash
# Vacuum single database
saved=$(vacuum_sqlite "$HOME/.mozilla/firefox/profile/places.sqlite")

# Vacuum all databases in current directory
clean_sqlite_dbs
```

**Browser Profiles:**
```bash
# Get Firefox default profile
profile=$(foxdir "$HOME/.mozilla/firefox")

# Get all Firefox profiles
mapfile -t profiles < <(mozilla_profiles "$HOME/.mozilla/firefox")

# Get Chromium roots (supports native, flatpak, snap)
mapfile -t roots < <(chrome_roots_for "chromium")

# Get Chromium profiles in a root
mapfile -t profiles < <(chrome_profiles "$root")
```

**Process Management:**
```bash
# Ensure browsers are closed before cleaning
ensure_not_running_any firefox chromium brave
```

---

### lib/debian.sh - Debian Library

**Platform-specific functions for Debian-based systems.**

Requires: `lib/base.sh`

#### Features:
- APT package manager detection (apt-get/apt-fast/nala)
- APT cleanup functions
- DietPi integration
- Debian system configuration
- Raspberry Pi specific functions
- F2FS filesystem support

#### Usage:
```bash
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/debian.sh" || exit 1
```

#### Key Functions:

**APT Operations:**
```bash
# Get best APT tool
apt_tool=$(get_apt_tool)  # Returns: nala, apt-fast, or apt-get

# Run APT command with best tool
run_apt update
run_apt install package1 package2

# Clean APT cache
clean_apt_cache

# Fix broken packages
fix_apt_packages
```

**DietPi Integration:**
```bash
# Check if running on DietPi
if is_dietpi; then
  load_dietpi_globals
  run_dietpi_update
  run_dietpi_cleanup
fi
```

**Raspberry Pi:**
```bash
# Check if running on Raspberry Pi
if is_raspberry_pi; then
  model=$(get_pi_model)
  is_pi_64bit && echo "64-bit OS"
fi
```

**System Configuration:**
```bash
# Configure dpkg to exclude docs
configure_dpkg_nodoc

# Remove existing documentation
clean_documentation
```

---

### lib/ui.sh - User Interface Library

**User interface functions for banners, menus, and text processing.**

Requires: `lib/base.sh`

#### Features:
- Banner printing with gradient effects
- Pre-defined ASCII art banners
- Text processing utilities
- Progress indicators
- Box drawing
- Simple menu system

#### Usage:
```bash
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/ui.sh" || exit 1
```

#### Key Functions:

**Banners:**
```bash
# Print predefined banner
print_named_banner "update" "Custom Title"
print_named_banner "clean"
print_named_banner "setup"
print_named_banner "fix"
print_named_banner "optimize"

# Print custom banner with gradient
banner=$(cat <<'EOF'
 Custom ASCII Art
 Goes Here
EOF
)
print_banner "$banner" "Title"
```

**Text Processing:**
```bash
# Remove comments and blank lines
cat file.conf | remove_comments

# Remove duplicate lines (preserving order)
cat file.txt | remove_duplicate_lines

# Extract URLs
cat file.txt | extract_urls

# Extract IP addresses
cat file.txt | extract_ips

# Normalize whitespace
cat file.txt | normalize_whitespace
```

**Progress Indicators:**
```bash
# Show spinner while command runs
long_running_command &
show_spinner $!

# Show progress bar
for i in {1..100}; do
  progress_bar $i 100 "Processing"
  sleep 0.1
done
```

**Menus:**
```bash
# Simple menu
choice=$(show_menu "Option 1" "Option 2" "Option 3")
echo "Selected: ${options[$choice]}"
```

**Box Drawing:**
```bash
draw_box "Title" "Line 1" "Line 2" "Line 3"
```

---

### lib/cleaning.sh - Cleaning Library

**System cleaning functions for cache, logs, and temporary files.**

Requires: `lib/base.sh`
Optional: `lib/arch.sh` (for advanced features)

#### Features:
- System cache cleanup
- Log rotation and cleanup
- Browser data cleanup (Firefox, Chromium families)
- Container cleanup (Docker/Podman)
- Package manager cache cleanup (pacman, apt, flatpak, snap)
- Language-specific caches (npm, pip, cargo, go, composer)
- SQLite optimization for browsers
- Aggregated cleanup functions

#### Usage:
```bash
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/cleaning.sh" || exit 1

# Optional: for browser profile detection
source "${SCRIPT_DIR}/../lib/arch.sh" || exit 1
```

#### Key Functions:

**Basic Cleanup:**
```bash
# Clean system caches
clean_cache_dirs

# Clean trash
clean_trash

# Clean logs
clean_journal_logs
clean_crash_dumps
clean_history_files
```

**Package Manager Cleanup:**
```bash
# Clean all package manager caches
clean_package_caches

# Clean language-specific caches
clean_language_caches
```

**Container Cleanup:**
```bash
# Clean Docker
clean_docker

# Clean Podman
clean_podman
```

**Browser Cleanup:**
```bash
# Ensure browsers are closed
ensure_browsers_closed

# Clean all browser caches
clean_all_browsers

# Vacuum browser SQLite databases
vacuum_browser_sqlite
```

**Aggregated Functions:**
```bash
# Basic cleanup (safe for all systems)
clean_all_basic

# Comprehensive cleanup
clean_all_comprehensive

# Deep clean (aggressive)
clean_all_deep

# User-space only (no sudo)
clean_user_only

# System-space only (requires sudo)
clean_system_only
```

---

## Best Practices

### 1. Always Source Required Libraries

```bash
#!/usr/bin/env bash
# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/arch.sh" || exit 1  # If needed
```

### 2. Use Library Functions Instead of Duplicating

**❌ Bad:**
```bash
has(){ command -v "$1" &>/dev/null; }
```

**✅ Good:**
```bash
# Just source lib/base.sh - has() is already defined
```

### 3. Follow Standard Script Structure

```bash
#!/usr/bin/env bash
# Script description
# Additional details about what this script does

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1

# ============================================================================
# Functions
# ============================================================================

my_function() {
  info "Doing something"
  # ...
  ok "Done"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
  # Initialize if needed
  PRIV_CMD=$(init_priv)

  # Setup traps
  trap cleanup EXIT INT TERM

  # Main logic
  my_function

  # Success
  ok "Script completed successfully"
}

main "$@"
```

### 4. Use Consistent Logging

```bash
# Information
info "Starting process..."

# Success
ok "Process completed"

# Warning
warn "This might take a while"

# Error (non-fatal)
err "An error occurred"

# Fatal error (exits)
die "Fatal error, exiting"

# Section header
section "Phase 2: Optimization"
```

### 5. Handle Privileges Correctly

```bash
# Initialize once at start
PRIV_CMD=$(init_priv)

# Use run_priv for commands that need elevation
run_priv systemctl restart service

# Or check if root is required
require_root || die "This script must be run as root"
```

### 6. Use Proper Error Handling

```bash
# Set errexit, nounset, pipefail
# Already done in lib/base.sh

# Use traps for cleanup
cleanup() {
  clean_paths "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

# Check command existence before using
if has git; then
  git pull
else
  warn "git not found, skipping update"
fi
```

---

## Migration Guide

### Converting Existing Scripts

1. **Remove duplicate color definitions** - use library colors
2. **Remove duplicate functions** - use library functions
3. **Remove environment setup** - handled by library
4. **Replace hard-coded privilege tools** - use `init_priv`/`run_priv`
5. **Replace inline package manager detection** - use library functions
6. **Replace cleanup logic** - use `lib/cleaning.sh` functions

### Example Migration

**Before:**
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

RED=$'\e[31m'
GRN=$'\e[32m'
DEF=$'\e[0m'

has(){ command -v "$1" &>/dev/null; }

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get clean
sudo apt-get autoremove -y
```

**After:**
```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/debian.sh" || exit 1

main() {
  PRIV_CMD=$(init_priv)

  info "Updating system"
  run_apt update
  run_apt upgrade -y

  info "Cleaning up"
  clean_apt_cache

  ok "Update complete"
}

main "$@"
```

---

## Validation

### Running Validation

```bash
# Validate all scripts
bash scripts/validate-all.sh

# Validate single script
bash -n script.sh

# Run shellcheck (if installed)
shellcheck script.sh

# Run shfmt (if installed)
shfmt -d script.sh
```

### ShellCheck Configuration

The repository includes `.shellcheckrc` with disabled checks for:
- SC2034: Variables that are exported
- SC2154: Variables from sourced files
- SC1091: Not following source files

---

## Examples

### Simple Update Script

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/arch.sh" || exit 1
source "${SCRIPT_DIR}/../lib/ui.sh" || exit 1

main() {
  PRIV_CMD=$(init_priv)
  print_named_banner "update" "System Update"

  info "Updating packages"
  pkgmgr=$(get_pkg_manager)
  mapfile -t aur_opts < <(get_aur_opts)

  run_priv "$pkgmgr" -Syu --noconfirm "${aur_opts[@]}"
  ok "Update complete"
}

main "$@"
```

### Simple Cleanup Script

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/cleaning.sh" || exit 1
source "${SCRIPT_DIR}/../lib/ui.sh" || exit 1

main() {
  PRIV_CMD=$(init_priv)
  print_named_banner "clean" "System Cleanup"

  # Close browsers
  ensure_browsers_closed

  # Run comprehensive cleanup
  clean_all_comprehensive

  ok "Cleanup complete"
}

main "$@"
```

---

## Troubleshooting

### Library Not Found

**Error:** `lib/base.sh: No such file or directory`

**Solution:** Check the relative path to lib/ from your script location

```bash
# From /Cachyos/script.sh
source "${SCRIPT_DIR}/../lib/base.sh"

# From /Cachyos/Scripts/script.sh
source "${SCRIPT_DIR}/../../lib/base.sh"

# From /RaspberryPi/script.sh
source "${SCRIPT_DIR}/../lib/base.sh"
```

### Function Not Found

**Error:** `command not found: function_name`

**Solution:** Make sure you've sourced the correct library:
- Core functions → `lib/base.sh`
- Arch-specific → `lib/arch.sh`
- Debian-specific → `lib/debian.sh`
- UI/banners → `lib/ui.sh`
- Cleaning → `lib/cleaning.sh`

### Permission Denied

**Error:** `Permission denied` when running privileged commands

**Solution:** Initialize privileges at the start:
```bash
PRIV_CMD=$(init_priv)
```

---

## Contributing

When adding new scripts:

1. Always source appropriate libraries
2. Don't duplicate existing functions
3. Follow the standard script structure
4. Add proper documentation
5. Test with `scripts/validate-all.sh`
6. Run shellcheck if available

When adding new functions:

1. Add to the appropriate library (not individual scripts)
2. Document the function with comments
3. Follow existing naming conventions
4. Test thoroughly

---

## See Also

- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Bash Best Practices](https://mywiki.wooledge.org/BashGuide/Practices)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
