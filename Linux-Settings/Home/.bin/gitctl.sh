#!/usr/bin/env bash
LC_ALL=C LANG=C

gitctl() {
  if [ $# -eq 0 ]; then
    echo "Usage: gitctl <git-repo-url> [directory]" >&2
    return 1
  fi
  local dir url="$1" 
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
  if command -v gix >/dev/null 2>&1; then
    gix clone "$url" "$dir" || return 1
  else
    # Clone the repo
    git clone --depth 1 --single-branch "$url" "$dir" || return 1
    #git clone --depth 1 --single-branch --shallow-submodules --filter='blob:none' "$url" "$dir" || return 1
    #git clone "$url" "$dir" || return 1
  fi
  # cd into the cloned repo
  cd "$dir" || return
  if [ -d "$dir" ]; then
    cd "$dir" || return
  return 0
  fi
}
