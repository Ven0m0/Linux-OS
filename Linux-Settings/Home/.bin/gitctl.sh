#!/bin/bash

gitctl() {
  if [ $# -eq 0 ]; then
    echo "Usage: gitctl <git-repo-url> [directory]" >&2
    return 1
  fi

  local url="$1"
  local dir

  # Use provided directory name or derive from URL
  if [ -n "$2" ]; then
    dir="$2"
  else
    # Strip trailing slashes and optional .git
    dir="$(basename "${url%%/}")"
    dir="${dir%.git}"
  fi

  # If the directory exists, just cd into it
  if [ -d "$dir" ]; then
    cd "$dir" || return
    return 0
  fi

  # Clone the repo
  git clone "$url" "$dir" || return 1

  # cd into the cloned repo
  cd "$dir" || return
}
