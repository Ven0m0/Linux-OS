#!/bin/bash

DOTFILES_DIR="$HOME/dotfiles"
PACKAGES_FILE="$(dirname "$0")/packages.txt"
LOG_FILE="/var/log/pkg-install.log"
PACMAN_LOCK="/var/lib/pacman/db.lck"
LOCK_TIMEOUT=180  # Maximum seconds to wait for lock to be released

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Ensure log file is writable
ensure_log_file() {
    if [ ! -f "$LOG_FILE" ]; then
        sudo touch "$LOG_FILE" 2>/dev/null || touch "$LOG_FILE" 2>/dev/null
    fi
    sudo chmod 666 "$LOG_FILE" 2>/dev/null || chmod 666 "$LOG_FILE" 2>/dev/null
    
    if [ ! -w "$LOG_FILE" ]; then
        echo "Warning: Cannot write to log file at $LOG_FILE, using temporary log"
        LOG_FILE="/tmp/pkg-install-$(date +%s).log"
        touch "$LOG_FILE"
    fi
}

# Enhanced Pacman Lock Handling
wait_for_pacman() {
    echo -ne "${BLUE}[PROGRESS]${NC} Checking for pacman lock... "
    
    if [ ! -f "$PACMAN_LOCK" ]; then
        echo -e "${GREEN}NO LOCK${NC}"
        return 0
    else
        echo -e "${YELLOW}LOCKED${NC}"
    fi
    
    local start_time=$(date +%s)
    local current_time
    local elapsed_time
    local lock_pid
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_idx=0
    
    while [ -f "$PACMAN_LOCK" ]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        
        # Try to find the process holding the lock
        lock_pid=$(fuser "$PACMAN_LOCK" 2>/dev/null)
        
        # Show animated spinner
        spin_char="${spinner[$spin_idx]}"
        spin_idx=$(( (spin_idx + 1) % 10 ))
        
        if [ -n "$lock_pid" ]; then
            lock_process=$(ps -p "$lock_pid" -o comm= 2>/dev/null)
            printf "\r${YELLOW}[WAITING]${NC} $spin_char Pacman locked by: $lock_process (PID: $lock_pid) - %3ds/%ds" "$elapsed_time" "$LOCK_TIMEOUT"
        else
            printf "\r${YELLOW}[WAITING]${NC} $spin_char Pacman locked (stale lock file) - %3ds/%ds" "$elapsed_time" "$LOCK_TIMEOUT"
        fi
        
        if [ "$elapsed_time" -gt "$LOCK_TIMEOUT" ]; then
            echo -e "\n${RED}[TIMEOUT]${NC} Lock timeout exceeded ($LOCK_TIMEOUT seconds)."
            force_remove_lock
            break
        fi
        
        sleep 0.1
    done
    
    echo -e "\n${GREEN}[READY]${NC} Pacman is free to use!"
}

# Force remove pacman lock if needed with enhanced checks
force_remove_lock() {
    print_warning "Pacman lock issue detected."
    
    # Check if the lock is stale
    local lock_pid=$(fuser "$PACMAN_LOCK" 2>/dev/null)
    if [ -z "$lock_pid" ]; then
        print_warning "Lock file exists but no process is using it (stale lock)."
        print_warning "Recommend removing the lock."
        local auto_remove="y"
    else
        print_warning "Lock is held by process $lock_pid."
        auto_remove="n"
    fi

    print_warning "Do you want to force remove the lock? (y/n) [$auto_remove]"
    read -r -t 10 response
    response=${response:-$auto_remove}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo rm -f "$PACMAN_LOCK"
        if [ ! -f "$PACMAN_LOCK" ]; then
            print_success "Pacman lock removed!"
            # Wait a moment to ensure system stability
            sleep 2
        else
            print_error "Failed to remove lock file. Check permissions."
            exit 1
        fi
    else
        print_error "Cannot proceed while pacman is locked."
        exit 1
    fi
}

# Update pacman database
update_pacman_db() {
    print_status "Updating package databases..."
    wait_for_pacman
    
    # Try up to 3 times to update the database
    for i in {1..3}; do
        echo -ne "${BLUE}[PROGRESS]${NC} Updating package databases (attempt $i/3)... "
        if sudo pacman -Sy &>> "$LOG_FILE"; then
            echo -e "${GREEN}SUCCESS${NC}"
            print_success "Package databases updated successfully."
            return 0
        else
            echo -e "${RED}FAILED${NC}"
            print_warning "Failed to update package databases (attempt $i/3)."
            
            # Check for common errors and provide more information
            if grep -q "could not lock database" "$LOG_FILE"; then
                print_warning "Database lock issue detected."
                wait_for_pacman
            elif grep -q "could not connect" "$LOG_FILE"; then
                print_warning "Network connection issue. Waiting before retry..."
            fi
            sleep 5
        fi
    done
    
    print_error "Failed to update package databases after multiple attempts."
    print_warning "Continuing with installation, but some packages might not be found."
    return 1
}

# Install AUR helper (paru or yay) with fallback options
install_aur_helper() {
    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
        print_success "Using existing AUR helper: $AUR_HELPER"
        return 0
    elif command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        print_success "Using existing AUR helper: $AUR_HELPER"
        return 0
    fi
    
    print_status "No AUR helper found. Installing paru..."
    sudo pacman -S --needed --noconfirm base-devel git || {
        print_error "Failed to install base dependencies for AUR helper."
        exit 1
    }
    
    # Try to install paru
    if [ -d "/tmp/paru" ]; then
        rm -rf "/tmp/paru"
    fi
    
    git clone https://aur.archlinux.org/paru.git /tmp/paru || {
        print_error "Failed to clone paru repository."
        print_warning "Trying to install yay instead..."
        install_yay
        return
    }
    
    cd /tmp/paru || exit 1
    makepkg -si --noconfirm || {
        print_error "Failed to build paru."
        cd - || exit 1
        print_warning "Trying to install yay instead..."
        install_yay
        return
    }
    
    cd - || exit 1
    rm -rf /tmp/paru
    
    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
        print_success "AUR helper (paru) installed successfully!"
    else
        print_error "Failed to install paru."
        install_yay
    fi
}

# Fallback to yay if paru fails
install_yay() {
    if [ -d "/tmp/yay" ]; then
        rm -rf "/tmp/yay"
    fi
    
    git clone https://aur.archlinux.org/yay.git /tmp/yay || {
        print_error "Failed to clone yay repository."
        print_error "Cannot install any AUR helper. AUR packages will be skipped."
        AUR_HELPER=""
        return 1
    }
    
    cd /tmp/yay || exit 1
    makepkg -si --noconfirm || {
        print_error "Failed to build yay."
        print_error "Cannot install any AUR helper. AUR packages will be skipped."
        AUR_HELPER=""
        cd - || exit 1
        return 1
    }
    
    cd - || exit 1
    rm -rf /tmp/yay
    
    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        print_success "AUR helper (yay) installed successfully!"
        return 0
    else
        print_error "Failed to install any AUR helper. AUR packages will be skipped."
        AUR_HELPER=""
        return 1
    fi
}

# Check if a package is installed with better error handling
is_package_installed() {
    if pacman -Qi "$1" &>/dev/null; then
        return 0
    elif [ -n "$AUR_HELPER" ] && $AUR_HELPER -Q "$1" &>/dev/null; then
        return 0
    fi
    return 1
}

# Install a single package from official repos
install_official_package() {
    local package="$1"
    local attempt=1
    local max_attempts=3
    
    while [ "$attempt" -le "$max_attempts" ]; do
        print_status "Installing $package (attempt $attempt/$max_attempts)..."
        wait_for_pacman
        
        echo -ne "${BLUE}[PROGRESS]${NC} Installing $package... "
        if sudo pacman -S --needed --noconfirm "$package" &>> "$LOG_FILE"; then
            echo -e "${GREEN}SUCCESS${NC}"
            print_success "$package installed successfully"
            return 0
        else
            echo -e "${RED}FAILED${NC}"
            if [ "$attempt" -lt "$max_attempts" ]; then
                print_warning "Failed to install $package. Retrying..."
                # If the package database might be corrupted, refresh it
                if grep -q "database .* is not valid" "$LOG_FILE"; then
                    print_warning "Invalid database detected. Refreshing..."
                    sudo pacman -Syy
                fi
                sleep 2
            else
                print_error "Failed to install $package after $max_attempts attempts"
                return 1
            fi
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

# Install a single package from AUR
install_aur_package() {
    local package="$1"
    
    if [ -z "$AUR_HELPER" ]; then
        print_error "No AUR helper available. Cannot install $package."
        return 1
    fi
    
    print_status "Installing $package from AUR..."
    wait_for_pacman
    
    echo -ne "${BLUE}[PROGRESS]${NC} Installing $package from AUR... "
    if $AUR_HELPER -S --needed --noconfirm "$package" &>> "$LOG_FILE"; then
        echo -e "${GREEN}SUCCESS${NC}"
        print_success "$package installed successfully from AUR"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        print_error "Failed to install $package from AUR"
        return 1
    fi
}

# Install packages with improved error handling and batch processing
install_packages() {
    print_status "Starting package installation process..."
    ensure_log_file
    
    if [ ! -f "$PACKAGES_FILE" ]; then
        print_error "packages.txt not found at $PACKAGES_FILE"
        exit 1
    fi

    # Filter out comments and empty lines
    grep -v "^#" "$PACKAGES_FILE" | grep -v "^$" > /tmp/filtered_packages.txt
    total_packages=$(wc -l < /tmp/filtered_packages.txt)
    
    print_status "Found $total_packages packages to process"

    read -p "Proceed with installation? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled"
        rm /tmp/filtered_packages.txt
        exit 0
    fi

    # Update package database
    update_pacman_db
    
    # Install AUR helper
    install_aur_helper

    # Sort packages into different categories
    to_install_pacman=$(mktemp)
    to_install_aur=$(mktemp)
    already_installed=$(mktemp)
    failed_packages=$(mktemp)
    unknown_packages=$(mktemp)

    echo -e "${BLUE}[PROGRESS]${NC} Analyzing packages..."
    local total_to_check=$(wc -l < /tmp/filtered_packages.txt)
    local current=0
    
    while IFS= read -r package || [ -n "$package" ]; do
        [[ -z "$package" ]] && continue
        
        current=$((current + 1))
        # Show progress every 5 packages or for the last one
        if [ $((current % 5)) -eq 0 ] || [ "$current" -eq "$total_to_check" ]; then
            echo -ne "${BLUE}[PROGRESS]${NC} Checking packages: $current/$total_to_check\r"
        fi
        
        if is_package_installed "$package"; then
            echo "$package" >> "$already_installed"
        elif pacman -Si "$package" &> /dev/null; then
            echo "$package" >> "$to_install_pacman"
        elif [ -n "$AUR_HELPER" ] && $AUR_HELPER -Si "$package" &> /dev/null; then
            echo "$package" >> "$to_install_aur"
        else
            echo "$package" >> "$unknown_packages"
            print_warning "Package not found in any repository: $package"
        fi
    done < /tmp/filtered_packages.txt
    echo -e "${GREEN}[DONE]${NC} Package analysis complete.                "
    
    rm /tmp/filtered_packages.txt

    # Batch install official packages when possible
    if [ -s "$to_install_pacman" ]; then
        print_status "Installing official repository packages..."
        
        # First try batch installation
        package_list=$(paste -sd " " "$to_install_pacman")
        wait_for_pacman
        
        if sudo pacman -S --needed --noconfirm $package_list &>> "$LOG_FILE"; then
            print_success "All official packages installed successfully in batch mode"
            cat "$to_install_pacman" > /tmp/succeeded_packages
        else
            print_warning "Batch installation failed. Falling back to individual installation."
            
            # Individual installation fallback
            while IFS= read -r package; do
                if install_official_package "$package"; then
                    echo "$package" >> /tmp/succeeded_packages
                else
                    echo "$package" >> "$failed_packages"
                fi
            done < "$to_install_pacman"
        fi
    fi

    # Install AUR packages individually (safer)
    if [ -s "$to_install_aur" ]; then
        aur_count=$(wc -l < "$to_install_aur")
        print_status "Installing $aur_count AUR packages:"
        cat "$to_install_aur" | sed 's/^/  - /'
        
        local count=0
        local total="$aur_count"
        
        while IFS= read -r package; do
            count=$((count + 1))
            echo -e "${BLUE}[PROGRESS]${NC} AUR Package $count/$total: $package"
            
            if install_aur_package "$package"; then
                echo "$package" >> /tmp/succeeded_packages
            else
                echo "$package" >> "$failed_packages"
            fi
        done < "$to_install_aur"
    fi

    # Add unknown packages to failed list
    if [ -s "$unknown_packages" ]; then
        cat "$unknown_packages" >> "$failed_packages"
    fi

    # Generate summary
    installed_count=$(wc -l < /tmp/succeeded_packages 2>/dev/null || echo 0)
    already_count=$(wc -l < "$already_installed")
    failed_count=$(wc -l < "$failed_packages")
    unknown_count=$(wc -l < "$unknown_packages")

    # Summary
    print_status "===========================================" 
    print_status "Installation Summary:"
    echo -e "  - ${BLUE}Total packages processed:${NC} $total_packages"
    echo -e "  - ${GREEN}Already installed:${NC} $already_count"
    echo -e "  - ${GREEN}Newly installed:${NC} $installed_count"
    echo -e "  - ${RED}Failed to install:${NC} $failed_count"
    echo -e "  - ${YELLOW}Unknown packages:${NC} $unknown_count"
    
    if [ -s "$failed_packages" ]; then
        print_error "Failed to install these packages:"
        cat "$failed_packages" | sed 's/^/    - /'
        print_warning "Check $LOG_FILE for details and install manually."
    fi

    # Cleanup
    rm -f "$to_install_pacman" "$to_install_aur" "$already_installed" "$failed_packages" "$unknown_packages" /tmp/succeeded_packages 2>/dev/null

    # Final system update check
    print_status "Checking for partial upgrades and consistency issues..."
    wait_for_pacman
    
    echo -ne "${BLUE}[PROGRESS]${NC} Running system consistency check... "
    if sudo pacman -Dk &>> "$LOG_FILE"; then
        echo -e "${GREEN}PASSED${NC}"
        print_success "System consistency check passed!"
    else
        echo -e "${YELLOW}ISSUES FOUND${NC}"
        print_warning "System has consistency issues."
        
        # Extract and display the actual issues
        echo -e "${YELLOW}[CONSISTENCY ISSUES]${NC}"
        grep "warning:" "$LOG_FILE" | tail -n 10 | sed 's/^/  /'
        echo
        print_warning "Consider running 'sudo pacman -Dk' to identify all problems."
    fi
    
    # Show timestamp for completion
    completion_time=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${GREEN}[COMPLETE]${NC} Package installation process completed at $completion_time"
    echo -e "${GREEN}[SUCCESS]${NC} All operations finished!"
}

# Handle script interruption with improved cleanup
cleanup() {
    echo
    print_warning "Installation interrupted!"
    print_warning "Cleaning up temporary files..."
    
    # Remove any temp files created by the script
    rm -f /tmp/filtered_packages.txt /tmp/succeeded_packages 2>/dev/null
    
    # Check if pacman might be in a broken state
    if pacman -Qi pacman &>/dev/null; then
        print_warning "Pacman appears to be functional."
    else
        print_error "Pacman may be in a broken state! Run 'sudo pacman -Syy' to refresh databases."
    fi
    
    exit 1
}

trap cleanup SIGINT SIGTERM

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_packages
fi
