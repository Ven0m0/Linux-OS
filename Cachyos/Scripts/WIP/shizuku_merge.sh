#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Merge Shizuku forks into your fork using upstream as base.
# Base upstream: thedjchi/Shizuku
# Your fork (assumed): Ven0m0/Shizuku (adjust USER_FORK if different)
# Other forks: yangFenTuoZi/Shizuku, pdien/Shizuku, Ryfters/Shizuku

USER_FORK="Ven0m0/Shizuku"
UPSTREAM="thedjchi/Shizuku"
FORKS=(
  "yangFenTuoZi/Shizuku"
  "pdien/Shizuku"
  "Ryfters/Shizuku"
)

MERGE_BRANCH="merged-forks"
WORKDIR="shizuku-merge"
RERERE=1

msg() { printf '%s\n' "$*" >&2; }

require() {
  command -v "$1" &> /dev/null || {
    msg "Missing dep: $1"
    exit 1
  }
}

require git

[[ -d $WORKDIR ]] && {
  msg "Directory $WORKDIR exists; remove or rename."
  exit 1
}

msg "Cloning your fork: $USER_FORK"
git clone "https://github.com/${USER_FORK}.git" "$WORKDIR"
cd "$WORKDIR"

msg "Adding upstream remote"
git remote add upstream "https://github.com/${UPSTREAM}.git" || :
git fetch --all --prune

primary_branch() {
  local remote=$1
  git for-each-ref --format='%(refname:strip=3)' "refs/remotes/${remote}" | grep -E '^(main|master)$' | head -n1
}

up_branch=$(primary_branch upstream)
[[ -z $up_branch ]] && {
  msg "Cannot detect upstream main/master"
  exit 1
}

origin_branch=$(primary_branch origin)
[[ -z $origin_branch ]] && origin_branch=$up_branch

[[ $RERERE -eq 1 ]] && git config rerere.enabled true || :

# Ensure local base matches upstream
git fetch upstream "$up_branch"
git checkout -B "$up_branch" "upstream/$up_branch"
git checkout -B "integration-base" "upstream/$up_branch"

# Add fork remotes
for f in "${FORKS[@]}"; do
  name="${f%%/*}"
  url="https://github.com/${f}.git"
  git remote add "$name" "$url" 2> /dev/null || :
done
git fetch --all --prune

# Collect branch + diff size
declare -A fork_branch diff_size
for f in "${FORKS[@]}"; do
  r="${f%%/*}"
  b=$(primary_branch "$r")
  [[ -z $b ]] && {
    msg "Skip $r (no main/master)"
    continue
  }
  fork_branch["$r"]="$b"
  # sum added+removed lines relative to upstream to order merges (small → big)
  s=$(git diff --numstat "upstream/$up_branch...$r/$b" | awk '{add+=$1;del+=$2} END{print add+del+0}')
  diff_size["$r"]=$s
done

# Order remotes
mapfile -t ordered < <(
  for k in "${!fork_branch[@]}"; do
    printf '%s %s\n' "${diff_size[$k]}" "$k"
  done | sort -n | awk '{print $2}'
)

msg "Merge order (smallest diff first): ${ordered[*]}"

merge_one() {
  local remote=$1
  local branch=${fork_branch[$remote]}
  git checkout integration-base
  git checkout -B "merge-${remote}" "integration-base"
  msg "Merging $remote/$branch"
  set +e
  git merge --no-ff --log "$remote/$branch" -m "Merge $remote/$branch"
  local status=$?
  set -e
  if ((status != 0)); then
    msg "Conflict in $remote. Resolve, then: git add -u; git commit --no-edit; git checkout integration-base; git merge --no-ff merge-${remote}"
    return 1
  fi
  # Fast-forward integration-base to include merge
  git checkout integration-base
  git merge --ff-only "merge-${remote}" || {
    msg "FF fail for $remote; investigate."
    return 1
  }
  return 0
}

for r in "${ordered[@]}"; do
  merge_one "$r" || {
    msg "Stop due to conflict. Fix then re-run from current state."
    exit 2
  }
done

# Final consolidation branch
git checkout -B "$MERGE_BRANCH" "integration-base"

# Optional squash (commented: preserves history now)
# git reset --soft "$(git merge-base upstream/$up_branch $MERGE_BRANCH)" || :
# git commit -m "Squashed unified changes from forks" || :

msg "Running basic sanity (Gradle if present)"
if [[ -f gradlew ]]; then
  chmod +x gradlew || :
  ./gradlew --quiet tasks &> /dev/null || msg "Gradle probe skipped/fail"
fi

msg "Pushing merge branch to origin (your fork)"
git push origin "$MERGE_BRANCH" || msg "Push failed; check auth."

cat << EOF
Done.
Create PR:
1. Go to: https://github.com/${UPSTREAM}/compare/${up_branch}...${USER_FORK}:${MERGE_BRANCH}
2. Title: Merge forks (yangFenTuoZi, pdien, Ryfters) into upstream base
3. Review diff; verify manifest, build.gradle, resources.
If conflicts occurred mid-run: resolve and re-run from merge point (do NOT reclone).
EOF
