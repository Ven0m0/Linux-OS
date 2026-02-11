#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'

# Helper functions
die() { printf '\e[31mERROR: %s\e[0m\n' "$*" >&2; exit 1; }
log() { printf '\e[34m:: %s\e[0m\n' "$*"; }
warn() { printf '\e[33m⚠ %s\e[0m\n' "$*" >&2; }
success() { printf '\e[32m✓ %s\e[0m\n' "$*"; }

confirm_or_exit() {
  while read -r -n1 key; do
    [[ $key == $'\e' ]] && exit 0
    break
  done
}

# Dependencies
command -v gh >/dev/null 2>&1 || die "Missing dependency: gh"
command -v git >/dev/null 2>&1 || die "Missing dependency: git"
JQ="jq"
command -v jaq >/dev/null 2>&1 && JQ="jaq"

# Download release assets
cmd_asset() {
  local repo="${1:-}" pattern="${2:-}" tag="" out=""
  [[ -z $repo || -z $pattern ]] && die "Usage: $0 asset OWNER/REPO PATTERN [-r TAG] [-o FILE]"
  shift 2
  OPTIND=1
  while getopts "r:o:s" opt; do
    case $opt in
      r) tag="$OPTARG" ;;
      o) out="$OPTARG" ;;
      s) exec >/dev/null ;;
      *) die "Invalid flag: -$OPTARG" ;;
    esac
  done
  local args=(release download "${tag:+$tag}" --repo "$repo" --pattern "$pattern" --clobber)
  [[ -n $out ]] && args+=("--output" "$out")
  gh "${args[@]}" || die "Download failed"
}

# Interactive release asset installation
cmd_install() {
  local repo="${1:-}" tag="" path="$HOME/.local/bin" assets selected tmp
  [[ -z $repo ]] && die "Usage: $0 install OWNER/REPO [-t TAG] [-p PATH]"
  shift 1
  OPTIND=1
  while getopts "t:p:" opt; do
    case $opt in
      t) tag="$OPTARG" ;;
      p) path="$OPTARG" ;;
      *) die "Invalid flag: -$OPTARG" ;;
    esac
  done

  [[ -d $path ]] || die "Installation path does not exist: $path"
  [[ -w $path ]] || die "Installation path not writable: $path"

  log "Fetching assets for $repo ${tag:+($tag)}..."
  mapfile -t assets < <(gh release view "${tag:-}" --repo "$repo" --json assets -q ".assets[].name")
  ((${#assets[@]} == 0)) && die "No assets found"

  echo "Select asset to install:"
  PS3="> "
  select selected in "${assets[@]}"; do
    [[ -n $selected ]] && break || echo "Invalid selection"
  done

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  gh release download "${tag:-}" --repo "$repo" --pattern "$selected" --output "$tmp/$selected" --clobber

  log "Installing to $path..."
  case "$selected" in
    *.tar.gz | *.tgz) tar -xzf "$tmp/$selected" -C "$path" ;;
    *.zip) unzip -q -o "$tmp/$selected" -d "$path" ;;
    *) install -m 755 "$tmp/$selected" "$path/" ;;
  esac
  success "Installed $selected to $path"
}

# Repository maintenance
cmd_maint() {
  local mode="both" dry=0 yes=0 c
  [[ ${1:-} =~ ^(clean|update|both)$ ]] && {
    mode=$1
    shift
  }
  OPTIND=1
  while getopts "dy" opt; do
    case $opt in
      d) dry=1 ;;
      y) yes=1 ;;
      *) die "Invalid flag: -$OPTARG" ;;
    esac
  done

  [[ $mode =~ update|both ]] && {
    log "Updating remotes..."
    ((dry)) || {
      git fetch --all -p
      git pull --autostash
    }
  }

  if [[ $mode =~ clean|both ]]; then
    log "Cleaning merged branches..."
    local -a branches
    mapfile -t branches < <(git branch --merged | grep -vE '^\*|master|main|dev')
    ((${#branches[@]} == 0)) && {
      log "No branches to clean"
      return
    }
    printf 'Branches to delete:\n%s\n' "${branches[*]}"
    ((dry)) && return
    ((yes)) || {
      read -rp "Confirm deletion? [y/N] " -n1 c
      echo
      [[ $c =~ [yY] ]] || return
    }
    git branch -d "${branches[@]}"
  fi
}

# Simple PR combination
cmd_combine() {
  (($# < 1)) && die "Usage: $0 combine-prs PR_NUMBER..."
  command -v awk >/dev/null 2>&1 || die "Missing dependency: awk"

  log "Preparing branch..."
  git fetch origin
  local base branch sha
  branch="combined-prs-$(date +%Y%m%d-%H%M%S)"
  base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
  git checkout -B "$branch" "origin/$base"

  for pr in "$@"; do
    log "Processing PR #$pr..."
    sha=$(git ls-remote origin "refs/pull/$pr/head" | awk '{print $1}')
    [[ -n $sha ]] || die "Could not resolve PR #$pr"
    git rev-list --reverse "origin/$base..$sha" | git cherry-pick --stdin --allow-empty ||
      die "Conflict processing PR #$pr. Resolve manually or skip."
  done
  success "Created branch: $branch"
  echo "To push: git push origin $branch --set-upstream"
}

# Advanced PR combination with query-based selection
cmd_combine_advanced() {
  local help_text='Usage: gh tools combine-advanced --query "QUERY" [OPTIONS]
Combines multiple PRs into one with advanced filtering and status checks.
Required: --query "QUERY" - Query to find combinable PRs (e.g., "author:app/dependabot")
Optional: --selected-pr-numbers N,N --limit N (default: 50) --skip-pr-check'

  local limit=50 query="" skip_pr_check="false" selected_pr_numbers=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        echo "$help_text"
        exit 0
        ;;
      --selected-pr-numbers)
        selected_pr_numbers="$2"
        shift 2
        ;;
      --limit)
        limit="$2"
        shift 2
        ;;
      --query)
        query="$2"
        shift 2
        ;;
      --skip-pr-check)
        skip_pr_check="true"
        shift
        ;;
      *)
        echo "$help_text" >&2
        exit 1
        ;;
    esac
  done

  [[ -z $query ]] && {
    echo "$help_text"
    die "--query is required"
  }

  local default_branch combined_branch body_file
  default_branch=$(gh api /repos/:owner/:repo --jq '.default_branch')
  combined_branch="combined-pr-branch-$(date +%Y%m%d-%H%M%S)"
  body_file=$(mktemp)
  trap 'rm -f "$body_file"' EXIT

  cat <<-'EOF' >"$body_file"
	Combining multiple dependencies PRs into one.
	<details><summary>Instructions for merging</summary>
	* **Use a merge commit**, so that GitHub will mark all original PRs as merged.
	* If your repository does not have merge commits enabled, please temporarily enable them in settings.
	* When ready, merge this PR using `Create a merge commit`.
	</details>
	## Combined PRs
	EOF

  log "The following PRs will be evaluated for inclusion:"
  gh pr list --search "$query" --limit "$limit"
  [[ $skip_pr_check == "true" ]] && log "Action status checks for PRs will be skipped"

  local jq_filter=".[]"
  [[ -n $selected_pr_numbers ]] && {
    log "Only the following PRs will be selected: $selected_pr_numbers"
    jq_filter="$jq_filter | select(.number == ($selected_pr_numbers))"
  }

  echo "Press any key to continue or escape to abort"
  confirm_or_exit

  git fetch
  git checkout "$default_branch"
  git pull --ff-only
  git branch -D "$combined_branch" 2>/dev/null || true
  git checkout -b "$combined_branch"

  local count=0 number headref description
  while IFS=$'\t' read -r number headref; do
    if [[ $skip_pr_check == "false" ]]; then
      local check_status
      check_status=$(gh pr checks "$number" | cut -d$'\t' -f2 | grep -cE "fail|pending" || echo "0")
      [[ $check_status -gt 0 ]] && {
        warn "Not all checks are passing - skipping PR #$number"
        continue
      }
    fi

    log "Trying to merge $headref into $combined_branch"
    if ! git merge "origin/$headref" --no-edit 2>/dev/null; then
      warn "Unable to merge $headref - skipping PR #$number"
      git merge --abort
      continue
    fi
    success "Merged $headref (#$number) into $combined_branch"

    description=$(gh pr view "$number" --json title,author,number --template '{{.title}} (#{{.number}}) @{{.author.login}}')
    echo "* $description" >>"$body_file"
    ((count++))
    [[ $count -ge $limit ]] && {
      log "Hit limit of $limit - no more PRs will be added"
      break
    }
  done < <(gh pr list --search "$query" --limit "$limit" --json headRefName,number | $JQ -r "$jq_filter | [.number,.headRefName] | @tsv")

  echo -e "\nPreview of PR:\n"
  cat "$body_file"
  echo -e "\n\nFinished merging - press any key to create PR or escape to abort"
  confirm_or_exit

  log "Creating PR"
  gh pr create --title "Combined dependencies PR" --body-file "$body_file" --label dependencies
}

# Update PR branches with latest changes
cmd_update_branch() {
  local help_text="Usage: gh tools update-branch [PR_NUMBER|--mine]
Updates PR branches with latest changes from the default branch.
Args: PR_NUMBER (defaults to current PR if omitted) | --mine (update all your PRs)"

  local prs number sha
  if [[ $# -eq 0 ]]; then
    prs=$(gh pr view --jq '.[].number' --json number)
    log "Updating current PR"
  elif [[ $1 == "--mine" ]]; then
    prs=$(gh pr list --author @me --jq '.[].number' --json number)
    log "Updating all your PRs"
  elif [[ $1 == "-h" || $1 == "--help" ]]; then
    echo "$help_text"
    exit 0
  else
    prs="$1"
    log "Updating specified PR"
  fi

  for pr in $prs; do
    read -r number sha < <(gh pr view "$pr" --json number,commits --jq '[.number,.commits[-1].oid]|@tsv')
    log "Updating PR #$number"
    if gh api --silent "repos/{owner}/{repo}/pulls/$number/update-branch" \
      --field expected_head_sha="$sha" \
      --method PUT; then
      success "Updated PR #$number"
    else
      warn "Failed to update PR #$number"
    fi
  done
}

# Force remove git submodules
cmd_submod_rm() {
  (($# < 1)) && die "Usage: $0 submod-rm PATH..."
  for path in "$@"; do
    [[ ! -e $path && ! -d ".git/modules/$path" ]] && {
      warn "Skipping invalid path: $path"
      continue
    }
    log "Removing submodule: $path"
    git submodule deinit -f "$path" >/dev/null 2>&1 || :
    git rm -f -r "$path"
    rm -rf ".git/modules/$path"
    success "Cleaned $path"
  done
}

usage() {
  cat <<EOF
gh-tools - Unified GitHub CLI Extension

Usage: ${0##*/} COMMAND [ARGS]

Asset Management:
  asset OWNER/REPO PATTERN [-r TAG] [-o FILE]
      Download release asset matching PATTERN
  install OWNER/REPO [-t TAG] [-p PATH]
      Interactive installation to PATH (default: ~/.local/bin)

Repository Maintenance:
  maint [clean|update|both] [-d] [-y]
      Clean merged branches and/or update remotes
      -d  Dry run (show what would be done)
      -y  Skip confirmation prompts

Pull Request Operations:
  combine-prs PR_ID [PR_ID...]
      Simple cherry-pick combination of multiple PRs
  combine-advanced --query "QUERY" [OPTIONS]
      Advanced PR combination with status checks
      --query "QUERY"              Search query (e.g., "author:app/dependabot")
      --selected-pr-numbers N,N    Only combine specific PR numbers
      --limit N                    Max PRs to combine (default: 50)
      --skip-pr-check              Skip status check validation
  update-branch [PR_NUMBER|--mine]
      Update PR branches with latest from default branch
      --mine   Update all your PRs

Git Utilities:
  submod-rm PATH [PATH...]
      Force remove git submodules

Examples:
  ${0##*/} asset cli/cli '*linux_amd64.tar.gz' -r v2.0.0
  ${0##*/} install sharkdp/bat
  ${0##*/} maint clean -y
  ${0##*/} combine-prs 123 456 789
  ${0##*/} combine-advanced --query "author:app/dependabot"
  ${0##*/} update-branch --mine
  ${0##*/} submod-rm vendor/old-lib

EOF
  exit "${1:-1}"
}

# Main dispatcher
[[ $# -eq 0 ]] && usage
CMD="$1"
shift

case "$CMD" in
  asset | install | maint) "cmd_$CMD" "$@" ;;
  combine-prs) cmd_combine "$@" ;;
  combine-advanced) cmd_combine_advanced "$@" ;;
  update-branch) cmd_update_branch "$@" ;;
  submod-rm) cmd_submod_rm "$@" ;;
  -h | --help) usage 0 ;;
  *) die "Unknown command: $CMD. Use -h for help." ;;
esac
