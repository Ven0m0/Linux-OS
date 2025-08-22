#!/usr/bin/env bash
# Speed up git
export LC_ALL=C LANG=C
jobs="$(nproc 2>/dev/null || echo 8)"

githousekeep(){
  local workdir
  workdir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
  cd -- "$workdir" || return 1
  local dir="${1:-$workdir}"
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Not a git work tree: %s\n' "$dir" >&2; return 1
  fi
  printf '\e[1mHousekeeping: %s\e[0m\n' "$dir"
  # Fetch from remote, twice in case something goes wrong
  git -C "$dir" fetch --prune --no-tags --filter=blob:none origin || git -C "$dir" fetch --prune --no-tags origin || :
  # Delete local branches that have been merged.
  git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads \
    --merged=origin/HEAD \
    | grep -Ev '^(main|master|dev|release|HEAD)$' \
    | xargs --no-run-if-empty -r -n1 git -C "$dir" branch -d 2>/dev/null || :
  # Prune origin: stop tracking branches that do not exist in origin
  git -C "$dir" remote prune origin >/dev/null || :
  # Ensure each submodule itself is forcibly synced to the remote tip and cleaned
  git -C "$dir" submodule foreach --recursive '
    echo "  Submodule: $name ($sm_path)"
    # fetch then force reset to remote default
    git fetch --prune --no-tags origin --depth=1 || git fetch --prune --no-tags origin || :
    git reset --hard origin/HEAD || :
    git clean -fdx || :
  '
  ## Optimize/Clean
  git -C "$dir" repack -adq --depth=250 --window=250 --cruft >/dev/null || :
  git -C "$dir" reflog expire --expire=now --all >/dev/null || :
  git -C "$dir" gc --auto --aggressive --prune=now >/dev/null || :
  git -C "$dir" clean -fdXq >/dev/null || :
}
gitdate(){
  local workdir
  workdir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
  cd -- "$workdir" || return 1
  local dir="${1:-$workdir}"
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Not a git work tree: %s\n' "$dir" >&2; return 1
  fi
  printf '\e[1mUpdating: %s\e[0m\n' "$dir"
  # Keep remote-tracking refs tidy
  git -C "$dir" remote prune origin >/dev/null
  # Fetch
  git -C "$dir" fetch --prune --no-tags --filter=blob:none origin || git -C "$dir" fetch --prune --no-tags origin || :
  # if rebase failed try to abort and continue
  git -C "$dir" pull --rebase --autostash --prune origin HEAD || git -C "$dir" rebase --abort &>/dev/null
  # Sync submodule URLs
  git -C "$dir" submodule sync --recursive || :
  # Update submodules with fallback
  git -C "$dir" submodule update --init --recursive --remote --filter=blob:none --depth 1 --single-branch --jobs "$jobs" \
    || git -C "$dir" submodule update --init --recursive --remote --depth 1 --jobs "$jobs" \
    || git -C "$dir" submodule update --init --recursive --remote --jobs "$jobs"
  printf '\e[1mUpdate complete: %s\e[0m\n' "$dir"
}
