#!/data/data/com.termux/files/usr/bin/bash
# Termux Butler - A comprehensive cleaning, maintenance, and optimization
# script for your Termux environment.
#
# Version: 1.0.0

# --- Globals & Configuration ---
set -o pipefail # Fail a pipe if any command fails

# Use a specific temporary directory for this script's operations
readonly SCRIPT_TMP_DIR=$(mktemp -d)
# Ensure the temporary directory is cleaned up on script exit
trap 'rm -rf -- "$SCRIPT_TMP_DIR"' EXIT

# Namerefs for easier configuration at the top
declare -n large_file_size_mb="CONFIG_LARGE_FILE_SIZE_MB"
declare -n large_file_search_path="CONFIG_LARGE_FILE_SEARCH_PATH"

# --- Configuration ---
# Minimum size in MB for a file to be considered "large"
CONFIG_LARGE_FILE_SIZE_MB=100
# Path to search for large files (default: Termux home)
CONFIG_LARGE_FILE_SEARCH_PATH="$HOME"

# --- UI & Logging ---

# Define colors for output using tput for compatibility
readonly C_RESET=$(tput sgr0)
readonly C_BOLD=$(tput bold)
readonly C_RED=$(tput setaf 1)
readonly C_GREEN=$(tput setaf 2)
readonly C_YELLOW=$(tput setaf 3)
readonly C_BLUE=$(tput setaf 4)
readonly C_MAGENTA=$(tput setaf 5)

# Logging functions for consistent messaging
_log() {
  local -r color="$1"
  local -r prefix="$2"
  local -r message="$3"
  echo -e "${color}${C_BOLD}${prefix}${C_RESET} ${message}"
}

log_info() { _log "$C_BLUE" "[*]" "$1"; }
log_ok() { _log "$C_GREEN" "[+]" "$1"; }
log_warn() { _log "$C_YELLOW" "[!]" "$1"; }
log_error() { _log "$C_RED" "[-]" "$1" >&2; }
log_header() {
  echo
  _log "$C_MAGENTA" "---" "$1"
  echo
}

# --- Core Functions ---

# Function to ask for user confirmation (Yes/No)
# Usage: confirm "Your question" && action_if_yes
confirm() {
  local prompt="${1:-Are you sure?}"
  while true; do
    read -p "$prompt [y/N] " response
    case "$response" in
    [yY][eE][sS] | [yY]) return 0 ;;
    [nN][oO] | [nN] | "") return 1 ;;
    *) log_warn "Please answer 'yes' or 'no'." ;;
    esac
  done
}

# Task: Update packages and clean the package cache
task_package_maintenance() {
  log_header "Package Maintenance"
  log_info "Updating package lists..."
  pkg update -y || log_error "Failed to update package lists."

  log_info "Upgrading installed packages..."
  pkg upgrade -y || log_error "Failed to upgrade packages."

  log_info "Cleaning up unused package dependencies..."
  pkg autoclean
  apt-get autoremove -y

  log_info "Clearing the local package cache..."
  apt clean
  log_ok "Package maintenance complete."
}

# Task: Clean various application and system caches
task_cache_cleanup() {
  log_header "Cache Cleanup"
  local -a cleaned_items=()

  if command -v uv &>/dev/null; then
    uv cache clean --force
    uv cache prune
  fi
  # Python pip cache
  if command -v pip &>/dev/null; then
    log_info "Purging pip cache..."
    pip cache purge &>/dev/null
    cleaned_items+=("pip")
  fi

  # NPM cache
  if [[ -d "$HOME/.npm" ]]; then
    log_info "Cleaning npm cache..."
    npm cache clean --force &>/dev/null
    cleaned_items+=("npm")
  fi

  # Generic user cache directory
  if [[ -d "$HOME/.cache" ]]; then
    log_info "Clearing user cache directory ($HOME/.cache)..."
    # Use find to remove contents safely
    find "$HOME/.cache" -mindepth 1 -delete
    cleaned_items+=("User Cache")
  fi

  # Termux temporary files
  if [[ -d "/data/data/com.termux/files/usr/tmp" ]]; then
    log_info "Clearing Termux temporary directory..."
    find "/data/data/com.termux/files/usr/tmp" -mindepth 1 -delete
    cleaned_items+=("Termux Tmp")
  fi

  log_ok "Cache cleanup finished. Items processed: ${cleaned_items[*]}"
}

# Task: Filesystem maintenance (empty files/dirs)
task_filesystem_hygiene() {
  log_header "Filesystem Hygiene"
  log_info "Searching for and removing empty directories..."
  local empty_dirs
  empty_dirs=$(find "$HOME" -type d -empty -print)
  if [[ -n $empty_dirs ]]; then
    echo "$empty_dirs"
    echo "$empty_dirs" | xargs -r rm -r
    log_ok "Removed empty directories."
  else
    log_info "No empty directories found."
  fi

  log_info "Searching for and removing empty files..."
  local empty_files
  empty_files=$(find "$HOME" -type f -empty -print)
  if [[ -n $empty_files ]]; then
    echo "$empty_files"
    echo "$empty_files" | xargs -r rm
    log_ok "Removed empty files."
  else
    log_info "No empty files found."
  fi
}

# Task: Find large files for manual review
task_find_large_files() {
  log_header "Find Large Files (>${large_file_size_mb}MB)"
  log_info "Searching in: $large_file_search_path"
  log_warn "This operation can be slow on large filesystems."

  # Use fd if available (much faster), otherwise fall back to find
  local find_cmd
  if command -v fd &>/dev/null; then
    find_cmd=(fd . "$large_file_search_path" --type f --size "+${large_file_size_mb}M")
  else
    find_cmd=(find "$large_file_search_path" -type f -size "+${large_file_size_mb}M")
  fi

  # Execute the find command and process the results
  local large_files
  large_files=$("${find_cmd[@]}" -exec du -h {} + | sort -rh)

  if [[ -n $large_files ]]; then
    log_ok "Found large files:"
    echo "--------------------------"
    echo "$large_files"
    echo "--------------------------"
    log_warn "Review these files and delete them manually if they are not needed."
  else
    log_info "No files larger than ${large_file_size_mb}MB found."
  fi
}

# Task: Rebuild the locate command's database
task_update_db() {
  log_header "Update Locate Database"
  if command -v updatedb &>/dev/null; then
    log_info "Running updatedb to index filesystem..."
    updatedb
    log_ok "Database updated."
  else
    log_warn "The 'updatedb' command was not found."
    log_info "To install it, run: pkg install findutils"
  fi
}

# --- Menu & Main Logic ---

# Display the main menu
show_menu() {
  echo
  echo -e "${C_BOLD}${C_MAGENTA}--- Termux Butler ---${C_RESET}"
  echo "1) Full Clean & Optimize (Recommended)"
  echo "2) Package Maintenance Only"
  echo "3) Cache Cleanup Only"
  echo "4) Filesystem Hygiene (Remove empty files/dirs)"
  echo "5) Find Large Files (>${large_file_size_mb}MB)"
  echo "6) Update Locate Database"
  echo "q) Quit"
  echo
}

# Main function to run the script
main() {
  while true; do
    show_menu
    read -p "Select an option: " choice
    case "$choice" in
    1)
      task_package_maintenance
      task_cache_cleanup
      task_filesystem_hygiene
      task_update_db
      log_ok "Full run complete!"
      ;;
    2)
      task_package_maintenance
      ;;
    3)
      task_cache_cleanup
      ;;
    4)
      task_filesystem_hygiene
      ;;
    5)
      task_find_large_files
      ;;
    6)
      task_update_db
      ;;
    [qQ])
      break
      ;;
    *)
      log_warn "Invalid option. Please try again."
      ;;
    esac
  done
  echo
  log_info "Termux Butler signing off. Have a great day!"
}

# --- Script Entrypoint ---
main "$@"
