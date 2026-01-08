#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

readonly CLI="gh-unified"
readonly VERSION="2.0.0"

has(){ command -v -- "$1" &>/dev/null; }
msg(){ printf '%s\n' "$@"; }
log(){ printf '%s\n' "$@" >&2; }
die(){ printf '%s\n' "$1" >&2; exit "${2:-1}"; }
confirm(){ local k; read -rsn1 k; [[ $k == $'\e' ]] && exit 0; }
choose(){
  [[ $# -eq 0 ]] && die "choose: no options"
  if has fzf; then printf '%s\n' "$@" | fzf --height=10 --prompt="${PS3}" -1
  else select o in "$@"; do [[ -n $o ]] && { echo "$o"; break; }; done; fi
}
extract(){
  local f=$1
  [[ ! -f $f ]] && { log "'$f' not a file"; return 1; }
  case $f in
    *.tar.bz2|*.tbz2) tar xjf "$f";;
    *.tar.gz|*.tgz) tar xzf "$f";;
    *.tar.xz|*.tar.zst) tar xf "$f";;
    *.bz2) bunzip2 "$f";;
    *.gz) gunzip "$f";;
    *.tar) tar xf "$f";;
    *.zip) unzip -q "$f";;
    *.Z) uncompress "$f";;
    *) log "'$f' cannot be extracted; assuming binary"; return 1;;
  esac
}
urlencode(){
  printf '%s\n' "$*" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/!/%21/g' -e 's/"/%22/g' \
    -e "s/'/%27/g" -e 's/#/%23/g' -e 's/(/%28/g' -e 's/)/%29/g' -e 's/+/%2b/g' \
    -e 's/,/%2c/g' -e 's/-/%2d/g' -e 's/:/%3a/g' -e 's/;/%3b/g' -e 's/?/%3f/g' \
    -e 's/@/%40/g' -e 's/\$/%24/g' -e 's/\&/%26/g' -e 's/\*/%2a/g' -e 's/\./%2e/g' \
    -e 's/\//%2f/g' -e 's/\[/%5b/g' -e 's/\\/%5c/g' -e 's/\]/%5d/g' -e 's/\^/%5e/g' \
    -e 's/_/%5f/g' -e 's/`/%60/g' -e 's/{/%7b/g' -e 's/|/%7c/g' -e 's/}/%7d/g' -e 's/~/%7e/g'
}
usage_main(){
  cat <<EOF
Usage: $CLI <command> [options]

Commands:
  merge-prs    Combine multiple PRs into one with squash support
  download     Download files/folders from GitHub without cloning
  install      Download & install binary from GitHub releases

Options:
  -h, --help    Show this help
  -v, --version Show version

Examples:
  $CLI merge-prs --squash
  $CLI download cli/cli .github
  $CLI install cli/cli
EOF
}
usage_merge(){
  cat <<'EOF'
Usage: gh-unified merge-prs [OPTIONS]

Combines multiple PRs into one with auto-squash support.

Options:
  --query "Q"           Query for PRs (default: "author:app/dependabot")
  --pr-numbers N1,N2... Comma-separated PR numbers
  --limit N             Max PRs to combine (default: 50)
  --skip-checks         Merge PRs even if checks aren't passing
  --squash              Squash all commits after merging
  --title "TITLE"       PR title (default: "Combined dependencies PR")
  --branch NAME         Branch name (default: "combined-pr-branch")
  -h, --help            Show this help

Examples:
  gh-unified merge-prs
  gh-unified merge-prs --squash --query "label:dependencies"
  gh-unified merge-prs --pr-numbers 42,13,78 --squash
EOF
}
usage_download(){
  cat <<EOF
Usage: $CLI download <repo> [<...paths>]
       $CLI download <url>

Download folders/files from GitHub without cloning.

Arguments:
  <repo>        username/repo (defaults to gh user if username missing)
  <...paths>    folder or file paths
  <url>         https://github.com/...

Options:
  -b, --branch <name>  Branch or tag (default: default branch)
  --outdir <path>      Output directory (single path only)
  --outfile <path>     Output file (single file only)
  -d, --dry-run        Report downloads without executing
  -h, --help           Show usage

Examples:
  $CLI download yuler/gh-download README.md
  $CLI download cli/cli .github
  $CLI download https://github.com/yuler/actions/tree/main/ci
EOF
}
usage_install(){
  cat <<EOF
Usage: $CLI install <repo>

Download & install binary from GitHub releases.

Arguments:
  <repo>    GitHub repository (username/repo)

Options:
  -h, --help    Show usage

Examples:
  $CLI install cli/cli
  $CLI install junegunn/fzf
EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# merge-prs: Combine multiple PRs into one
# ──────────────────────────────────────────────────────────────────────────────
cmd_merge_prs(){
  local query="author:app/dependabot" limit=50 skip_checks=false squash=false
  local title="Combined dependencies PR" branch="combined-pr-branch" pr_numbers=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage_merge; exit 0;;
      --query) query=$2; shift 2;;
      --pr-numbers) pr_numbers=$2; shift 2;;
      --limit) limit=$2; shift 2;;
      --skip-checks) skip_checks=true; shift;;
      --squash) squash=true; shift;;
      --title) title=$2; shift 2;;
      --branch) branch=$2; shift 2;;
      *) die "Unknown option: $1";;
    esac
  done
  local default_branch body_file
  default_branch=$(gh api /repos/:owner/:repo --jq '.default_branch') || die "Failed to fetch default branch"
  body_file=$(mktemp)
  trap 'rm -f "$body_file"' EXIT
  local jq_filter=".[]"
  [[ -n $pr_numbers ]] && jq_filter="$jq_filter | select(.number == ($pr_numbers))"
  msg "PRs matching query '$query':"
  gh pr list --search "$query" --limit "$limit" || die "No PRs found"
  [[ $skip_checks == true ]] && log "⚠️  Check validation disabled"
  [[ $squash == true ]] && log "✓ Will squash commits after merge"
  [[ -n $pr_numbers ]] && log "Filtering to PRs: $pr_numbers"
  msg "Press any key to continue or ESC to abort..."
  confirm
  git fetch --all --prune
  git checkout "$default_branch"
  git pull --ff-only
  git branch -D "$branch" &>/dev/null || true
  git checkout -b "$branch"
  cat >"$body_file" <<'EOF'
Combining multiple dependencies PRs into one.

<details>
<summary>Merge Instructions</summary>

* **Use a merge commit** to mark all original PRs as merged
* Temporarily enable merge commits in settings if needed
* Merge with "Create a merge commit"

</details>

## Combined PRs

EOF
  local count=0 merged_prs=() number headref desc
  while IFS=$'\t' read -r number headref; do
    if [[ $skip_checks == false ]]; then
      if gh pr checks "$number" 2>/dev/null | cut -f2 | grep -qE "fail|pending"; then
        log "⊘ Skipping PR #$number (checks not passing)"
        continue
      fi
    fi
    log "→ Merging origin/$headref (#$number)..."
    if ! git merge "origin/$headref" --no-edit &>/dev/null; then
      log "⊘ Merge conflict in PR #$number, skipping"
      git merge --abort &>/dev/null || true
      continue
    fi
    desc=$(gh pr view "$number" --json title,author,number --template '{{.title}} (#{{.number}}) @{{.author.login}}')
    printf '* %s\n' "$desc" >>"$body_file"
    merged_prs+=("$number")
    log "✓ Merged PR #$number"
    ((++count))
    [[ $count -eq $limit ]] && { log "Hit limit of $limit PRs"; break; }
  done < <(gh pr list --search "$query" --limit "$limit" --json headRefName,number | jq -r "$jq_filter | [.number,.headRefName] | @tsv")
  [[ $count -eq 0 ]] && die "No PRs were merged"
  if [[ $squash == true ]]; then
    log "Squashing $count commits..."
    git reset --soft "$default_branch"
    git commit -m "$title" -m "Merged PRs: ${merged_prs[*]}"
  fi
  msg ""
  msg "=== PR Body Preview ==="
  cat "$body_file"
  msg ""
  msg "Press any key to push and create PR or ESC to abort..."
  confirm
  git push --set-upstream origin "$branch" --force
  gh pr create --title "$title" --body-file "$body_file" --label dependencies
  msg "✓ Combined PR created: $title"
  msg "  Branch: $branch"
  msg "  Merged: $count PRs"
  [[ $squash == true ]] && msg "  Commits: squashed"
}

# ──────────────────────────────────────────────────────────────────────────────
# install: Download & install release binary
# ──────────────────────────────────────────────────────────────────────────────
cmd_install(){
  [[ $# -eq 0 ]] && { usage_install; exit 1; }
  local repo=$1
  case $1 in
    -h|--help) usage_install; exit 0;;
  esac
  local tmp binpath="${GH_BINPATH:-$HOME/.local/bin}"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/gh-install.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  log "[repo] $repo"
  PS3="> Select version: "
  local -a tags
  mapfile -t tags < <(gh api "repos/$repo/releases" --jq '.[].tag_name')
  [[ ${#tags[@]} -eq 0 ]] && die "No releases found"
  local tag
  tag=$(choose "${tags[@]}")
  log "[version] $tag"
  PS3="> Select file: "
  local -a files
  mapfile -t files < <(gh api "repos/$repo/releases" --jq ".[] | select(.tag_name == \"$tag\") | .assets[].name")
  [[ ${#files[@]} -eq 0 ]] && die "No assets found for $tag"
  local filename
  filename=$(choose "${files[@]}")
  log "[filename] $filename"
  log "[*] Downloading $filename..."
  gh release download "$tag" --repo "$repo" --pattern "$filename" --dir "$tmp"
  cd "$tmp"
  if [[ $filename == *.deb ]]; then
    log "[*] Installing debian package..."
    sudo apt install "./$filename"
    return
  fi
  log "[*] Extracting..."
  local bin
  if extract "$filename"; then
    PS3="> Select binary: "
    local -a bins
    mapfile -t bins < <(find . -type f ! -name "$filename" -printf '%P\n')
    [[ ${#bins[@]} -eq 0 ]] && die "No binaries found in archive"
    bin=$(choose "${bins[@]}")
  else
    bin=$filename
  fi
  local basename="${bin##*/}" name
  read -rp "> Choose name (empty=$basename): " name
  mkdir -p "$binpath"
  local target="$binpath/${name:-$basename}"
  mv "$bin" "$target"
  chmod +x "$target"
  msg "Success! Saved in: $target"
}

# ──────────────────────────────────────────────────────────────────────────────
# download: Download files/folders from GitHub
# ──────────────────────────────────────────────────────────────────────────────
cmd_download(){
  local -a urls=() positional=()
  local repo branch outdir outfile dry_run token
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage_download; exit 0;;
      -d|--dry-run) dry_run=true; shift;;
      -b|--branch) branch=$2; shift 2;;
      --outdir) outdir=$2; shift 2;;
      --outfile) outfile=$2; shift 2;;
      *) positional+=("$1"); shift;;
    esac
  done
  set -- "${positional[@]}"
  [[ $# -eq 0 ]] && { usage_download; exit 1; }
  token=$(gh auth token -h github.com)
  collect_file(){
    local file=$1 folder=${2:-} dest=${3:-}
    [[ -z $folder ]] && folder=$(dirname "$file")
    if [[ -z $dest && -n ${outdir:-} && -n $folder ]]; then
      [[ $folder == "." ]] && dest="$outdir/$file" || dest="${file/$folder/$outdir}"
    fi
    [[ -n ${outfile:-} ]] && dest=$outfile
    [[ -z $dest ]] && dest=$file
    log "Collection file: \`$file\` → \`$dest\`"
    urls+=("https://raw.githubusercontent.com/$repo/$branch/$(urlencode "$file")" "$dest")
  }
  collect_folder(){
    local folder=$1
    log "Collection folder: \`$folder\`..."
    local -a files
    mapfile -t files < <(gh api "repos/$repo/git/trees/$branch?recursive=1" \
      --jq ".tree[] | select(.type == \"blob\") | .path | select(startswith(\"$folder/\"))")
    local f
    for f in "${files[@]}"; do collect_file "$f" "$folder"; done
  }
  download_all(){
    [[ ${#urls[@]} -eq 0 ]] && { log "No files to download"; return; }
    local -a args=(--location --create-dirs --oauth2-bearer "$token" --parallel-immediate --parallel)
    local i
    for ((i=0; i<${#urls[@]}; i+=2)); do
      args+=(--url "${urls[i]}" --output "${urls[i+1]}")
    done
    if [[ ${dry_run:-} == true ]]; then log "[dry-run] curl ${args[*]}"
    else curl "${args[@]}"; fi
  }
  local url_regex='^https://github.com/([A-Za-z0-9_-]+)/([A-Za-z0-9._-]+)/(tree|blob)/([A-Za-z0-9._/-]+)/(.*)$'
  if [[ $# -eq 1 && $1 =~ $url_regex ]]; then
    repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    branch="${BASH_REMATCH[4]}"
    local path="${BASH_REMATCH[5]}"
    log "[repo] $repo"
    log "[branch] $branch"
    case "${BASH_REMATCH[3]}" in
      tree) collect_folder "$path";;
      blob) collect_file "$path";;
    esac
    download_all
    return
  fi
  repo=$1; shift
  if [[ ! $repo =~ / ]]; then
    local username
    username=$(gh config get -h github.com user)
    repo="$username/$repo"
  fi
  [[ -z ${branch:-} ]] && branch=$(gh api "repos/$repo" --jq .default_branch)
  log "[repo] $repo"
  log "[branch] $branch"
  if [[ $# -eq 1 ]]; then
    local path=$1 folder
    [[ $path =~ /$ ]] && folder="${path%/}" || \
      folder=$(gh api "repos/$repo/git/trees/$branch?recursive=1" \
        --jq ".tree[] | select(.type == \"tree\") | .path | select(.==\"$path\")")
    if [[ -n $folder ]]; then collect_folder "$folder"
    else collect_file "$path"; fi
    download_all
    return
  fi
  unset outfile outdir
  local path folder
  for path in "$@"; do
    [[ $path =~ /$ ]] && folder="${path%/}" || \
      folder=$(gh api "repos/$repo/git/trees/$branch?recursive=1" \
        --jq ".tree[] | select(.type == \"tree\") | .path | select(.==\"$path\")")
    if [[ -n $folder ]]; then collect_folder "$folder"
    else collect_file "$path"; fi
  done
  download_all
}

# ──────────────────────────────────────────────────────────────────────────────
# Main router
# ──────────────────────────────────────────────────────────────────────────────
main(){
  has gh || die "gh CLI not found. Install from https://cli.github.com/"
  [[ $# -eq 0 ]] && { usage_main; exit 0; }
  case $1 in
    -h|--help) usage_main; exit 0;;
    -v|--version) echo "$CLI v$VERSION"; exit 0;;
    merge-prs) shift; cmd_merge_prs "$@";;
    download) shift; cmd_download "$@";;
    install) shift; cmd_install "$@";;
    *) die "Unknown command: $1";;
  esac
}

main "$@"
