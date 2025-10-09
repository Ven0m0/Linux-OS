#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C

# Default config locations in order of preference
CONFIG_PATHS=(
  "./android-toolkit-config.toml"
  "${HOME}/.config/android-toolkit/config.toml"
)

# Find and load the first available config file
find_config() {
  local config_file=""
  for path in "${CONFIG_PATHS[@]}"; do
    if [[ -r "$path" ]]; then
      config_file="$path"
      break
    fi
  done
  printf '%s\n' "$config_file"
}

# Parse the config file sections into associative arrays
parse_config() {
  local config_file="$1"
  local current_section=""
  
  # Reset all arrays
  declare -gA PERMISSIONS=()
  declare -gA COMPILATIONS=()
  
  # Early return if config doesn't exist
  [[ ! -r "$config_file" ]] && return 1
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Detect section headers [section]
    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi
    
    # Skip if we're not in a recognized section
    [[ "$current_section" != "permission" && "$current_section" != "compilation" ]] && continue
    
    # Parse key=value pair
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      
      # Store in appropriate array based on section
      case "$current_section" in
        permission)
          PERMISSIONS["$key"]="$value"
          ;;
        compilation)
          COMPILATIONS["$key"]="$value"
          ;;
      esac
    fi
  done < "$config_file"
  
  return 0
}

# Apply permission to a single app
set_apk_permission() {
  local apk="$1" mode="$2"
  
  case "$mode" in
    dump)
      adb shell pm grant "$apk" android.permission.DUMP
      echo "Granted DUMP to $apk"
      ;;
    write)
      adb shell pm grant "$apk" android.permission.WRITE_SECURE_SETTINGS
      echo "Granted WRITE_SECURE_SETTINGS to $apk"
      ;;
    doze)
      adb shell dumpsys deviceidle whitelist +"$apk"
      echo "Whitelisted $apk for doze"
      ;;
    *)
      echo "Unknown permission mode: $mode"
      return 1
      ;;
  esac
}

# Compile a single app
compile_apk() {
  local apk="$1" priority="$2" mode="$3"
  
  adb shell cmd package compile --full -r cmdline -p "$priority" -m "$mode" "$apk"
  echo "Compiled $apk with priority $priority and mode $mode"
}

# Apply all permissions from config
apply_permissions() {
  local connected
  connected=$(adb get-state 2>/dev/null) || { echo "No device connected"; return 1; }
  
  echo "Applying permissions from config..."
  for app in "${!PERMISSIONS[@]}"; do
    local perms="${PERMISSIONS[$app]}"
    local perm_array
    # Split comma-separated permissions into array
    IFS=',' read -ra perm_array <<< "$perms"
    
    for perm in "${perm_array[@]}"; do
      set_apk_permission "$app" "$perm"
    done
  done
}

# Apply compilation settings from config
apply_compilations() {
  local connected
  connected=$(adb get-state 2>/dev/null) || { echo "No device connected"; return 1; }
  
  echo "Applying compilation settings from config..."
  for app in "${!COMPILATIONS[@]}"; do
    local config="${COMPILATIONS[$app]}"
    local priority mode
    
    # Parse priority:mode format
    IFS=':' read -r priority mode <<< "$config"
    
    compile_apk "$app" "$priority" "$mode"
  done
}

# Save changes to config file
save_config() {
  local config_file="$1"
  local temp_file="${config_file}.tmp"
  
  # Create temporary file
  {
    echo "# Android Toolkit Configuration"
    echo "# Auto-generated on $(date)"
    echo ""
    echo "[permission]"
    for app in "${!PERMISSIONS[@]}"; do
      echo "$app=${PERMISSIONS[$app]}"
    done
    echo ""
    echo "[compilation]"
    for app in "${!COMPILATIONS[@]}"; do
      echo "$app=${COMPILATIONS[$app]}"
    done
  } > "$temp_file"
  
  # Move temp file to config file
  mv "$temp_file" "$config_file"
  echo "Saved config to $config_file"
}

# Add an app to the permission config
add_permission() {
  local app="$1" modes="$2"
  
  if [[ -v PERMISSIONS["$app"] ]]; then
    # Merge existing permissions with new ones
    local existing="${PERMISSIONS["$app"]}"
    local new_perms="$existing"
    
    # Add each new permission if not already present
    IFS=',' read -ra mode_array <<< "$modes"
    for mode in "${mode_array[@]}"; do
      if [[ "$existing" != *"$mode"* ]]; then
        new_perms="${new_perms:+$new_perms,}$mode"
      fi
    done
    
    PERMISSIONS["$app"]="$new_perms"
  else
    # Add new app with permissions
    PERMISSIONS["$app"]="$modes"
  fi
}

# Add an app to the compilation config
add_compilation() {
  local app="$1" priority="$2" mode="$3"
  
  COMPILATIONS["$app"]="$priority:$mode"
}

# Show usage info
show_usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  apply                  Apply all settings from config (default)
  permissions            Apply only permission settings
  compilations           Apply only compilation settings
  set-permission APP MODE[,MODE...]
                         Set permission(s) for an app (dump, write, doze)
  set-compilation APP PRIORITY MODE
                         Set compilation settings for an app
  list                   List current config settings
  help                   Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") permissions
  $(basename "$0") set-permission com.example.app dump,write
  $(basename "$0") set-compilation com.example.app PRIORITY_INTERACTIVE_FAST speed-profile

EOF
}

# Main functionality
main() {
  local config_file action="${1:-apply}"
  
  # Show help if requested
  if [[ "$action" == "help" || "$action" == "--help" || "$action" == "-h" ]]; then
    show_usage
    exit 0
  fi
  
  # Find config file
  config_file=$(find_config)
  if [[ -z "$config_file" && "$action" != "init" ]]; then
    echo "No config file found. Creating default at ${CONFIG_PATHS[0]}"
    mkdir -p "$(dirname "${CONFIG_PATHS[0]}")"
    touch "${CONFIG_PATHS[0]}"
    config_file="${CONFIG_PATHS[0]}"
  fi
  
  # Parse config if it exists
  if [[ -r "$config_file" ]]; then
    parse_config "$config_file"
  else
    declare -gA PERMISSIONS=()
    declare -gA COMPILATIONS=()
  fi
  
  case "$action" in
    apply|"")
      apply_permissions
      apply_compilations
      ;;
    permissions)
      apply_permissions
      ;;
    compilations)
      apply_compilations
      ;;
    set-permission)
      if [[ $# -lt 3 ]]; then
        echo "Usage: $(basename "$0") set-permission APP MODE[,MODE...]"
        exit 1
      fi
      add_permission "$2" "$3"
      save_config "$config_file"
      
      # Apply the permission immediately if requested
      if [[ $# -ge 4 && "$4" == "--apply" ]]; then
        IFS=',' read -ra perm_array <<< "$3"
        for perm in "${perm_array[@]}"; do
          set_apk_permission "$2" "$perm"
        done
      fi
      ;;
    set-compilation)
      if [[ $# -lt 4 ]]; then
        echo "Usage: $(basename "$0") set-compilation APP PRIORITY MODE"
        exit 1
      fi
      add_compilation "$2" "$3" "$4"
      save_config "$config_file"
      
      # Apply the compilation immediately if requested
      if [[ $# -ge 5 && "$5" == "--apply" ]]; then
        compile_apk "$2" "$3" "$4"
      fi
      ;;
    list)
      echo "Current configuration ($config_file):"
      echo ""
      echo "Permissions:"
      for app in "${!PERMISSIONS[@]}"; do
        echo "  $app: ${PERMISSIONS[$app]}"
      done
      echo ""
      echo "Compilations:"
      for app in "${!COMPILATIONS[@]}"; do
        echo "  $app: ${COMPILATIONS[$app]}"
      done
      ;;
    *)
      echo "Unknown command: $action"
      show_usage
      exit 1
      ;;
  esac
}

# Allow sourcing without executing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
