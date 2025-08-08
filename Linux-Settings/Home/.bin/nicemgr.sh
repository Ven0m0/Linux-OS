#!/usr/bin/env bash
# nice mgr: Check or adjust the nice values of specific processes or list all processes sorted by nice.
# https://www.reddit.com/r/bash/comments/1migur6/process_priority_manager
# Usage:
#   nicemgr checkALL
#   nicemgr <process-name> check
#   nicemgr <process-name> <niceValue>
#
#   checkALL      List PID, nice, and command for all processes sorted by nice (asc).
#   check         Show current nice value(s) for <process-name>.
#   niceValue     Integer from -20 (highest) to 20 (lowest) to renice matching processes.
#
# Note: Negative nice values require root or the process owner.

set -euo pipefail

# Ensure required commands are available
for cmd in pgrep ps sort renice uname; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' command not found. Please install it." >&2
    exit 1
  fi
done

# Describe a nice value in human-friendly terms
priority_desc() {
  local nv=$1
  case $nv in
    -20) echo "top priority." ;;
    -19|-18|-17|-16|-15|-14|-13|-12|-11|-10)
         echo "high priority level \"$nv\"." ;;
    -9|-8|-7|-6|-5|-4|-3|-2|-1)
         echo "priority level \"$nv\"." ;;
     0) echo "standard priority." ;;
     1|2|3|4|5|6|7|8|9|10)
         echo "background priority \"$nv\"." ;;
    11|12|13|14|15|16|17|18|19)
         echo "low priority \"$nv\"." ;;
     20) echo "lowest priority." ;;
     *)  echo "nice value \"$nv\" out of range." ;;
  esac
}

# Print usage and exit
usage() {
  cat <<EOF >&2
Usage: $(basename "$0") checkALL
       $(basename "$0") <process-name> check
       $(basename "$0") <process-name> <niceValue>

checkALL      List PID, nice, and command for all processes sorted by nice (asc).
check         Show current nice value(s) for <process-name>.
niceValue     Integer from -20 (highest) to 20 (lowest) to renice matching processes.

Note: Negative nice values require root or the process owner.
EOF
  exit 1
}

# Detect OS for ps options
OS=$(uname)
if [ "$OS" = "Linux" ]; then
  PS_LIST_OPTS=( -eo pid,ni,comm )    # GNU ps
elif [ "$OS" = "Darwin" ]; then
  PS_LIST_OPTS=( axo pid,ni,comm )    # BSD ps on macOS
else
  echo "Unsupported OS: $OS" >&2
  exit 1
fi

# Must have at least one argument
if [ $# -lt 1 ]; then
  usage
fi

# Global all-process check
if [ "$1" = "checkALL" ]; then
  ps "${PS_LIST_OPTS[@]}" | sort -n -k2
  exit 0
fi

# Per-process operations expect exactly two arguments
if [ $# -ne 2 ]; then
  usage
fi

proc_name=$1
action=$2

# Find PIDs matching process name (exact match)
# Using read -a for compatibility with Bash 3.x
read -r -a pids <<< "$(pgrep -x "$proc_name" || echo)"
# Ensure we have at least one non-empty PID
if [ ${#pids[@]} -eq 0 ] || [ -z "${pids[0]:-}" ]; then
  echo "No processes found matching '$proc_name'." >&2
  exit 1
fi

# Show current nice values
if [ "$action" = "check" ]; then
  for pid in "${pids[@]}"; do
    nice_val=$(ps -o ni= -p "$pid" | tr -d ' ')
    echo "$proc_name \"PID: $pid\" is currently set to $(priority_desc "$nice_val")"
  done
  exit 0
fi

# Renice if numeric argument
if [[ "$action" =~ ^-?[0-9]+$ ]]; then
  if (( action < -20 || action > 20 )); then
    echo "Error: nice value must be between -20 and 20." >&2
    exit 1
  fi
  for pid in "${pids[@]}"; do
    if renice "$action" -p "$pid" &>/dev/null; then
      echo "$proc_name \"PID: $pid\" has been adjusted to $(priority_desc "$action")"
    else
      echo "Failed to renice PID $pid (permission denied?)" >&2
    fi
  done
  exit 0
fi

# Invalid action provided
echo "Invalid action: must be 'check' or a numeric nice value." >&2
usage
