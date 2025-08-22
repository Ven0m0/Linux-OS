#!/usr/bin/env bash

# Speed up git
export LC_ALL=C LANG=C

githousekeep(){
  local workdir
  workdir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
  cd -- "$workdir" || return 1
  local dir="${1:-$workdir}"
  if [[ ! -d "$dir" ]] || [[ ! -d "${dir}/.git" ]]; then
    printf 'Not a git repo: %s\n' "$dir" >&2; return 1    
  fi
  printf '\e[1m housekeeping: %s\e[0m\n' "$dir"
  # Fetch from remote, twice in case something goes wrong
  git -C "$dir" fetch --prune --no-tags origin || git -C "$dir" fetch --prune --no-tags origin
  # Delete local (non-important) branches that have been merged.
  git -C "$dir" branch --merged \
          | grep -E -v "(^\*|HEAD|master|main|dev|release)" \
          | xargs --no-run-if-empty git branch -d
  # Prune origin: stop tracking branches that do not exist in origin
  git -C "$dir" remote prune origin >/dev/null
  ## Optimize
  git -C "$dir" repack -adq --depth=250 --window=250 --cruft >/dev/null
  git -C "$dir" reflog expire --expire=now --all >/dev/null
  git -C "$dir" gc --auto --aggressive --prune=now >/dev/null
  git -C "$dir" clean -fdXq >/dev/null
  fi
}
gitdate(){
  local workdir
  workdir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
  cd -- "$workdir" || return 1
  local dir="${1:-$workdir}"
  if [ ! -d "$dir" ] || [ ! -d "${dir}/.git" ]; then
    printf 'Not a git repo: %s\n' "$dir" >&2
    return 1
  fi
  printf '\e[1mUpdating: %s\e[0m\n' "$dir"
  local jobs
  jobs="$(LC_ALL=C LANG=C nproc 2>/dev/null || echo 8)"
  # Prune and fetch
  git -C "$dir" remote prune origin >/dev/null
  git -C "$dir" fetch --prune --no-tags origin || git -C "$dir" fetch --prune --no-tags origin
  # Pull
  git -C "$dir" pull -r --prune origin HEAD || {
    # If rebase fails, abort and continue
    git -C "$dir" rebase --abort &>/dev/null || :
  }
  # Remove any untracked files including ignored files (fully clean)
  git -C "$dir" clean -fdXq >/dev/null
  # Sync submodule URLs
  git -C "$dir" submodule sync --recursive
  # Update submodules
  git -C "$dir" submodule update --init --recursive --remote --depth 1 --single-branch --jobs "$jobs" || {
    # Fallback to non-shallow update if any submodule doesn't support depth/single-branch
    git -C "$dir" submodule update --init --recursive --remote || :
  }
  # Ensure each submodule itself is forcibly synced to the remote tip and cleaned
  git -C "$dir" submodule foreach --recursive '
    # fetch then force reset to remote default
    git fetch --prune --no-tags origin || true
    git reset --hard origin/HEAD || true
    git clean -fdx || true
  '
  printf '\e[1mUpdate complete: %s\e[0m\n' "$dir"
}
