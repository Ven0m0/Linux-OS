#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C
has(){ command -v -- "$1" &>/dev/null; }
msg(){ printf '%s\n' "$@"; }
log(){ printf '%s\n' "$@" >&2; }
die(){ printf '%s\n' "$1" >&2; exit "${2:-1}"; }

usage(){
cat << 'EOF'
Usage: gh merge-prs [OPTIONS]

Combines multiple PRs into one, with auto-squash support.

Options:
  --query "QUERY"           Query for PRs (default: "author:app/dependabot")
  --pr-numbers N1,N2,...    Comma-separated PR numbers to merge
  --limit N                 Max PRs to combine (default: 50)
  --skip-checks             Merge PRs even if checks aren't passing
  --squash                  Squash all commits after merging
  --title "TITLE"           PR title (default: "Combined dependencies PR")
  --branch NAME             Target branch name (default: "combined-pr-branch")
  -h, --help                Show this help

Examples:
  gh merge-prs                                    # Merge all dependabot PRs
  gh merge-prs --squash                           # Merge and squash
  gh merge-prs --query "label:dependencies"       # Custom query
  gh merge-prs --pr-numbers 42,13,78 --squash    # Specific PRs with squash
EOF
}

confirm(){
  local key
  read -rsn1 key
  [[ $key == $'\e' ]] && exit 0
}

# Defaults
QUERY="author:app/dependabot"
LIMIT=50
SKIP_CHECKS=false
SQUASH=false
TITLE="Combined dependencies PR"
BRANCH="combined-pr-branch"
PR_NUMBERS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --query) QUERY=$2; shift 2 ;;
    --pr-numbers) PR_NUMBERS=$2; shift 2 ;;
    --limit) LIMIT=$2; shift 2 ;;
    --skip-checks) SKIP_CHECKS=true; shift ;;
    --squash) SQUASH=true; shift ;;
    --title) TITLE=$2; shift 2 ;;
    --branch) BRANCH=$2; shift 2 ;;
    *) die "Unknown option: $1" ;;
  esac
done

has gh || die "gh CLI not found. Install from https://cli.github.com/"

# Get default branch
DEFAULT_BRANCH=$(gh api /repos/:owner/:repo --jq '.default_branch') || die "Failed to fetch default branch"
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

# Build JQ filter for PR selection
JQ_FILTER=".[]"
[[ -n $PR_NUMBERS ]] && JQ_FILTER="$JQ_FILTER | select(.number == ($PR_NUMBERS))"

# Preview PRs
msg "PRs matching query '$QUERY':"
gh pr list --search "$QUERY" --limit "$LIMIT" || die "No PRs found"
[[ $SKIP_CHECKS == true ]] && log "⚠️  Check validation disabled"
[[ $SQUASH == true ]] && log "✓ Will squash commits after merge"
[[ -n $PR_NUMBERS ]] && log "Filtering to PRs: $PR_NUMBERS"
msg "Press any key to continue or ESC to abort..."
confirm

# Prepare branch
git fetch --all --prune
git checkout "$DEFAULT_BRANCH"
git pull --ff-only

git branch -D "$BRANCH" &>/dev/null || true
git checkout -b "$BRANCH"

# Generate PR body header
cat > "$BODY_FILE" << 'EOF'
Combining multiple dependencies PRs into one.

<details>
<summary>Merge Instructions</summary>

* **Use a merge commit** to mark all original PRs as merged
* Temporarily enable merge commits in settings if needed
* Merge with "Create a merge commit"

</details>

## Combined PRs

EOF

# Process PRs
count=0
merged_prs=()
while IFS=$'\t' read -r number headref; do
  # Validate checks unless skipped
  if [[ $SKIP_CHECKS == false ]]; then
    if gh pr checks "$number" 2>/dev/null | cut -f2 | grep -qE "fail|pending"; then
      log "⊘ Skipping PR #$number (checks not passing)"
      continue
    fi
  fi

  # Attempt merge
  log "→ Merging origin/$headref (#$number)..."
  if ! git merge "origin/$headref" --no-edit &>/dev/null; then
    log "⊘ Merge conflict in PR #$number, skipping"
    git merge --abort &>/dev/null || true
    continue
  fi

  # Record merged PR
  desc=$(gh pr view "$number" --json title,author,number --template '{{.title}} (#{{.number}}) @{{.author.login}}')
  printf '* %s\n' "$desc" >> "$BODY_FILE"
  merged_prs+=("$number")
  log "✓ Merged PR #$number"

  ((++count))
  [[ $count -eq $LIMIT ]] && { log "Hit limit of $LIMIT PRs"; break; }
done < <(gh pr list --search "$QUERY" --limit "$LIMIT" --json headRefName,number | jq -r "$JQ_FILTER | [.number,.headRefName] | @tsv")

[[ $count -eq 0 ]] && die "No PRs were merged"

# Squash commits if requested
if [[ $SQUASH == true ]]; then
  log "Squashing $count commits..."
  git reset --soft "$DEFAULT_BRANCH"
  git commit -m "$TITLE" -m "Merged PRs: ${merged_prs[*]}"
fi

# Preview and confirm
msg ""
msg "=== PR Body Preview ==="
cat "$BODY_FILE"
msg ""
msg "Press any key to push and create PR or ESC to abort..."
confirm

# Push and create PR
git push --set-upstream origin "$BRANCH" --force
gh pr create --title "$TITLE" --body-file "$BODY_FILE" --label dependencies

msg "✓ Combined PR created: $TITLE"
msg "  Branch: $BRANCH"
msg "  Merged: $count PRs"
[[ $SQUASH == true ]] && msg "  Commits: squashed"
