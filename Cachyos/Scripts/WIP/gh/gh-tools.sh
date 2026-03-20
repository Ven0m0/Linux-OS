#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Colors (trans palette)
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
YLW=$'\e[33m' RED=$'\e[31m' GRN=$'\e[32m' DEF=$'\e[0m' BLD=$'\e[1m'

has(){ command -v "$1" &>/dev/null; }
log(){ printf "${LBLU}:: %s${DEF}\n" "$*"; }
warn(){ printf "${YLW}⚠ %s${DEF}\n" "$*" >&2; }
err(){ printf "${RED}ERROR: %s${DEF}\n" "$*" >&2; }
die(){ err "$*"; exit 1; }
success(){ printf "${GRN}✓ %s${DEF}\n" "$*"; }

# jq or drop-in replacement
JQ=$(command -v jaq || command -v jq || true)
[[ -n $JQ ]] || die "Missing dependency: jq (or jaq)"

# Read a single keypress; return 1 on Escape
_readkey(){
  [[ -t 0 ]] || return 0  # not a TTY — treat as confirmed
  local key
  local old
  old=$(stty -g)
  stty -echo -icanon min 1 time 0
  IFS= read -r -n1 key || true
  stty "$old"
  [[ $key == $'\e' ]] && return 1
  return 0
}

# Prompt user; abort if Escape pressed
confirm_or_exit(){
  printf '%s' "${YLW}Press any key to continue or Escape to abort...${DEF} "
  _readkey || { printf '\nAborted.\n'; exit 0; }
  printf '\n'
}

# Download release assets
cmd_asset(){
  local repo=${1:-} pattern=${2:-} tag="" out=""
  [[ -n $repo && -n $pattern ]] \
    || die "Usage: ${0##*/} asset OWNER/REPO PATTERN [-r TAG] [-o FILE]"
  shift 2

  OPTIND=1
  while getopts "r:o:s" opt; do
    case $opt in
      r) tag=$OPTARG;;
      o) out=$OPTARG;;
      s) exec >/dev/null;;
      *) die "Invalid flag: -$OPTARG";;
    esac
  done

  local -a args=(release download ${tag:+"$tag"} --repo "$repo" --pattern "$pattern" --clobber)
  [[ -n $out ]] && args+=("--output" "$out")
  gh "${args[@]}" || die "Download failed"
}

# Interactive release asset installation
cmd_install(){
  local repo=${1:-} tag="" path="$HOME/.local/bin"
  [[ -n $repo ]] || die "Usage: ${0##*/} install OWNER/REPO [-t TAG] [-p PATH]"
  shift

  OPTIND=1
  while getopts "t:p:" opt; do
    case $opt in
      t) tag=$OPTARG;;
      p) path=$OPTARG;;
      *) die "Invalid flag: -$OPTARG";;
    esac
  done

  [[ -d $path ]] || die "Installation path does not exist: $path"
  [[ -w $path ]] || die "Installation path not writable: $path"

  log "Fetching assets for $repo${tag:+ ($tag)}..."
  local -a assets
  mapfile -t assets < <(gh release view ${tag:+"$tag"} --repo "$repo" --json assets -q '.assets[].name')
  (( ${#assets[@]} > 0 )) || die "No assets found"

  local selected
  echo "Select asset to install:"
  PS3="> "
  select selected in "${assets[@]}"; do
    [[ -n $selected ]] && break || echo "Invalid selection"
  done

  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  gh release download ${tag:+"$tag"} --repo "$repo" --pattern "$selected" \
    --output "$tmp/$selected" --clobber

  log "Installing to $path..."
  case $selected in
    *.tar.gz|*.tgz) tar -xzf "$tmp/$selected" -C "$path";;
    *.zip)          unzip -q -o "$tmp/$selected" -d "$path";;
    *)              install -m 755 "$tmp/$selected" "$path/";;
  esac
  success "Installed $selected to $path"
}

# Repository maintenance: update remotes and/or clean merged branches
cmd_maint(){
  local mode="both" dry=0 yes=0

  if [[ ${1:-} =~ ^(clean|update|both)$ ]]; then
    mode=$1; shift
  fi

  OPTIND=1
  while getopts "dy" opt; do
    case $opt in
      d) dry=1;;
      y) yes=1;;
      *) die "Invalid flag: -$OPTARG";;
    esac
  done

  if [[ $mode =~ update|both ]]; then
    log "Updating remotes..."
    (( dry )) || { git fetch --all -p; git pull --autostash; }
  fi

  if [[ $mode =~ clean|both ]]; then
    log "Cleaning merged branches..."
    local -a branches
    mapfile -t branches < <(git branch --merged | grep -vE '^\*|master|main|dev')
    if (( ${#branches[@]} == 0 )); then
      log "No branches to clean"
      return
    fi
    printf 'Branches to delete:\n'
    printf '  %s\n' "${branches[@]}"
    (( dry )) && return
    if (( !yes )); then
      local c
      read -rp "Confirm deletion? [y/N] " -n1 c
      printf '\n'
      [[ $c =~ [yY] ]] || return
    fi
    git branch -d "${branches[@]}"
  fi
}

# Cherry-pick a list of PRs by number onto a new branch
cmd_combine(){
  (( $# >= 1 )) || die "Usage: ${0##*/} combine-prs PR_NUMBER..."
  has awk || die "Missing dependency: awk"

  log "Preparing branch..."
  git fetch origin

  local base branch sha
  base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^refs/remotes/origin/@@' || printf 'main')
  branch="combined-prs-$(date +%Y%m%d-%H%M%S)"
  git checkout -B "$branch" "origin/$base"

  for pr in "$@"; do
    log "Processing PR #$pr..."
    sha=$(git ls-remote origin "refs/pull/$pr/head" | awk '{print $1}')
    [[ -n $sha ]] || die "Could not resolve PR #$pr"
    git rev-list --reverse "origin/$base..$sha" \
      | git cherry-pick --stdin --allow-empty \
      || die "Conflict in PR #$pr. Resolve manually or skip."
  done

  success "Created branch: $branch"
  printf 'To push: git push -u origin %s\n' "$branch"
}

# Query-based PR combination with merge + status checks
cmd_combine_advanced(){
  local limit=50 query="" skip_pr_check=false yes=false

  while (( $# )); do
    case $1 in
      -h|--help)
        printf 'Usage: %s combine-advanced --query "QUERY" [--limit N] [--prs N,N] [--skip-pr-check] [-y]\n' "${0##*/}"
        exit 0;;
      --query)            query=${2:?missing query}; shift 2;;
      --selected-pr-numbers|--prs) selected_pr_numbers=${2:?missing numbers}; shift 2;;
      --limit)            limit=${2:?missing limit}; shift 2;;
      --skip-pr-check)    skip_pr_check=true; shift;;
      -y|--yes)           yes=true; shift;;
      *) die "Unknown option: $1. Use -h for help.";;
    esac
  done

  [[ -n $query ]] || die "--query is required"

  local default_branch combined_branch body_file
  default_branch=$(gh api /repos/:owner/:repo --jq '.default_branch')
  combined_branch="combined-pr-$(date +%Y%m%d-%H%M%S)"

  body_file=$(mktemp)
  trap 'rm -f "$body_file"' EXIT

  cat <<-'BODY' >"$body_file"
	Combining multiple dependency PRs into one.

	<details><summary>Merge instructions</summary>

	Use **Create a merge commit** so GitHub marks all original PRs as merged.
	If merge commits are disabled, enable them temporarily in repository settings.
	</details>

	## Combined PRs
	BODY

  log "Evaluating PRs matching: $query"
  gh pr list --search "$query" --limit "$limit"
  [[ $skip_pr_check == true ]] && warn "CI check validation is disabled"

  local jq_filter=".[]"
  if [[ -n ${selected_pr_numbers:-} ]]; then
    log "Restricting to PR numbers: $selected_pr_numbers"
    jq_filter="$jq_filter | select(.number == ($selected_pr_numbers))"
  fi

  if [[ $yes != true ]]; then
    confirm_or_exit
  fi

  git fetch
  git checkout "$default_branch"
  git pull --ff-only
  git branch -D "$combined_branch" 2>/dev/null || :
  git checkout -b "$combined_branch"

  local count=0 number headref description check_status
  while IFS=$'\t' read -r number headref; do
    if [[ $skip_pr_check == false ]]; then
      check_status=$(gh pr checks "$number" | cut -d$'\t' -f2 | grep -cE "fail|pending" || printf '0')
      if (( check_status > 0 )); then
        warn "Checks failing for PR #$number — skipping"
        continue
      fi
    fi

    log "Merging $headref (#$number)..."
    if ! git merge "origin/$headref" --no-edit 2>/dev/null; then
      warn "Merge conflict on $headref — skipping PR #$number"
      git merge --abort
      continue
    fi
    success "Merged $headref (#$number)"

    description=$(gh pr view "$number" \
      --json title,author,number \
      --template '{{.title}} (#{{.number}}) @{{.author.login}}')
    printf '* %s\n' "$description" >>"$body_file"
    (( ++count ))

    if (( count >= limit )); then
      log "Hit limit of $limit — stopping"
      break
    fi
  done < <(gh pr list --search "$query" --limit "$limit" \
    --json headRefName,number | "$JQ" -r "$jq_filter | [.number,.headRefName] | @tsv")

  (( count > 0 )) || die "No PRs were merged"

  printf '\nPreview of PR body:\n\n'
  cat "$body_file"

  if [[ $yes != true ]]; then
    printf '\n'
    confirm_or_exit
  fi

  log "Creating combined PR..."
  gh pr create \
    --title "Combined dependencies PR" \
    --body-file "$body_file" \
    --label dependencies
  success "Combined PR created with $count PR(s)"
}

# Update PR branch(es) to latest default branch changes
cmd_update_branch(){
  local prs_raw number sha

  if (( $# == 0 )); then
    prs_raw=$(gh pr view --jq '.[].number' --json number)
    log "Updating current PR"
  elif [[ $1 == "--mine" ]]; then
    prs_raw=$(gh pr list --author @me --jq '.[].number' --json number)
    log "Updating all your PRs"
  elif [[ $1 == "-h" || $1 == "--help" ]]; then
    printf 'Usage: %s update-branch [PR_NUMBER|--mine]\n' "${0##*/}"
    exit 0
  else
    prs_raw=$1
    log "Updating PR #$1"
  fi

  local -a pr_list
  mapfile -t pr_list <<<"$prs_raw"

  for pr in "${pr_list[@]}"; do
    [[ -z $pr ]] && continue
    read -r number sha < <(
      gh pr view "$pr" --json number,commits \
        --jq '[.number,.commits[-1].oid] | @tsv'
    )
    log "Updating PR #$number..."
    if gh api --silent "repos/{owner}/{repo}/pulls/$number/update-branch" \
        --field expected_head_sha="$sha" \
        --method PUT; then
      success "Updated PR #$number"
    else
      warn "Failed to update PR #$number"
    fi
  done
}

# Force-remove git submodule(s)
cmd_submod_rm(){
  (( $# >= 1 )) || die "Usage: ${0##*/} submod-rm PATH..."
  local path
  for path in "$@"; do
    if [[ ! -e $path && ! -d ".git/modules/$path" ]]; then
      warn "Skipping invalid path: $path"
      continue
    fi
    log "Removing submodule: $path"
    git submodule deinit -f "$path" >/dev/null 2>&1 || :
    git rm -f -r "$path"
    rm -rf ".git/modules/$path"
    success "Cleaned $path"
  done
}

usage(){
  cat <<EOF
${BLD}gh-tools${DEF} — Unified GitHub CLI Extension

Usage: ${0##*/} COMMAND [ARGS]

${LBLU}Asset Management${DEF}
  asset OWNER/REPO PATTERN [-r TAG] [-o FILE]
      Download release asset matching PATTERN
  install OWNER/REPO [-t TAG] [-p PATH]
      Interactive release asset installation (default path: ~/.local/bin)

${LBLU}Repository Maintenance${DEF}
  maint [clean|update|both] [-d] [-y]
      Clean merged branches and/or update remotes
      -d  Dry run   -y  Skip confirmation

${LBLU}Pull Request Operations${DEF}
  combine-prs PR_ID [PR_ID...]
      Cherry-pick combination of specific PRs
  combine-advanced --query "QUERY" [--limit N] [--prs N,N] [--skip-pr-check] [-y]
      Query-based PR combination with status checks
  update-branch [PR_NUMBER|--mine]
      Update PR branch(es) to latest from default branch

${LBLU}Git Utilities${DEF}
  submod-rm PATH [PATH...]
      Force remove git submodule(s)

${LBLU}Examples${DEF}
  ${0##*/} asset cli/cli '*linux_amd64.tar.gz' -r v2.0.0
  ${0##*/} install sharkdp/bat
  ${0##*/} maint clean -y
  ${0##*/} combine-prs 123 456 789
  ${0##*/} combine-advanced --query "author:app/dependabot" -y
  ${0##*/} update-branch --mine
  ${0##*/} submod-rm vendor/old-lib

EOF
  exit "${1:-1}"
}

# ── Dispatcher ──────────────────────────────────────────────────────────────
has gh  || die "Missing dependency: gh"
has git || die "Missing dependency: git"

(( $# > 0 )) || usage
CMD=$1; shift

case $CMD in
  asset)            cmd_asset "$@";;
  install)          cmd_install "$@";;
  maint)            cmd_maint "$@";;
  combine-prs)      cmd_combine "$@";;
  combine-advanced) cmd_combine_advanced "$@";;
  update-branch)    cmd_update_branch "$@";;
  submod-rm)        cmd_submod_rm "$@";;
  -h|--help)        usage 0;;
  --version)        printf 'gh-tools 2.0.0\n'; exit 0;;
  *) die "Unknown command: $CMD. Use -h for help.";;
esac
