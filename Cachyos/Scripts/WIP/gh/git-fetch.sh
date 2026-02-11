#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'

# Helper functions
die() { printf '\e[31mERROR: %s\e[0m\n' "$*" >&2; exit 1; }
log() { printf '\e[34m:: %s\e[0m\n' "$*"; }
success() { printf '\e[32m✓ %s\e[0m\n' "$*"; }
warn() { printf '\e[33m⚠ %s\e[0m\n' "$*"; }

# Dependencies
command -v gh >/dev/null 2>&1 || die "Missing dependency: gh"
command -v curl >/dev/null 2>&1 || die "Missing dependency: curl"
command -v jq >/dev/null 2>&1 || die "Missing dependency: jq"

# URL encode filenames for safe downloads
urlencode_filename() {
  echo "$@" | sed \
    -e 's/%/%25/g' -e 's/ /%20/g' -e 's/!/%21/g' -e 's/"/%22/g' -e "s/'/%27/g" -e 's/#/%23/g' \
    -e 's/(/%28/g' -e 's/)/%29/g' -e 's/+/%2b/g' -e 's/,/%2c/g' -e 's/:/%3a/g' -e 's/;/%3b/g' \
    -e 's/?/%3f/g' -e 's/@/%40/g' -e 's/\$/%24/g' -e 's/\&/%26/g' -e 's/\*/%2a/g' -e 's/\./%2e/g' \
    -e 's/\//%2f/g' -e 's/\[/%5b/g' -e 's/\\/%5c/g' -e 's/\]/%5d/g' -e 's/\^/%5e/g' -e 's/_/%5f/g' \
    -e 's/`/%60/g' -e 's/{/%7b/g' -e 's/|/%7c/g' -e 's/}/%7d/g' -e 's/~/%7e/g'
}

# Parse GitHub URLs
parse_github_url() {
  local url="$1"
  local regex='^https://github\.com/([A-Za-z0-9_-]+)/([A-Za-z0-9._-]+)/(tree|blob)/([A-Za-z0-9._/-]+)/(.+)$'
  [[ $url =~ $regex ]] && {
    PARSED_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    PARSED_BRANCH="${BASH_REMATCH[4]}"
    PARSED_PATH="${BASH_REMATCH[5]}"
    PARSED_IS_FOLDER=$([[ ${BASH_REMATCH[3]} == "tree" ]] && echo "true" || echo "false")
    return 0
  }
  return 1
}

# Resolve git ref (branch/commit/tag)
resolve_ref() {
  local repo="$1" branch="${2:-}" commit="${3:-}"
  [[ -n $commit ]] && echo "$commit" ||
    [[ -n $branch ]] && echo "$branch" ||
    gh api "repos/$repo" --jq '.default_branch' 2>/dev/null || echo "main"
}

# Get GitHub authentication token
get_github_token() {
  local token="${GITHUB_TOKEN:-}"
  [[ -z $token ]] && {
    token=$(gh auth token -h github.com 2>/dev/null) || die "No GitHub token. Run: gh auth login"
  }
  echo "$token"
}

# Collect all files in a folder
collect_folder_files() {
  local repo="$1" branch="$2" folder="$3" tree_output file
  log "Collecting files from folder: $folder"
  tree_output=$(gh api "repos/$repo/git/trees/$branch?recursive=1" --jq '.tree[] | select(.type == "blob") | .path' 2>/dev/null) ||
    die "Failed to fetch folder contents for $repo@$branch"
  while IFS= read -r file; do
    [[ $file == "$folder"* || $file == "$folder/"* ]] && echo "$file"
  done <<<"$tree_output"
}

# Download files using curl in parallel
download_files() {
  local repo="$1" branch="$2" token="$3" force="$4" output_dir="$5" dest encoded_path file
  shift 5
  local -a paths=("$@") curl_args=() skipped=() downloaded=()

  for path in "${paths[@]}"; do
    dest="$output_dir/$path"
    [[ -f $dest && $force != "true" ]] && {
      skipped+=("$path")
      continue
    }
    mkdir -p "$(dirname "$dest")"
    encoded_path=$(urlencode_filename "$path")
    curl_args+=("https://raw.githubusercontent.com/$repo/$branch/$encoded_path" "-o" "$dest")
    downloaded+=("$path")
  done

  ((${#skipped[@]} > 0)) && {
    warn "Skipped ${#skipped[@]} existing file(s) (use --force to overwrite):"
    printf '  %s\n' "${skipped[@]}" >&2
  }

  ((${#curl_args[@]} > 0)) && {
    log "Downloading ${#downloaded[@]} file(s)..."
    if curl --location --create-dirs --parallel --parallel-max 32 \
      --retry 3 --retry-delay 1 --oauth2-bearer "$token" \
      "${curl_args[@]}" 2>/dev/null; then
      for file in "${downloaded[@]}"; do
        success "$file"
      done
    else
      die "Download failed. Check network connection and permissions."
    fi
  }
}

# Add downloaded files to current git repository
add_to_repo() {
  local auto_commit="$1" message="$2" file file_list
  shift 2
  local -a files=("$@") staged=()

  git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository. Run: git init"
  log "Staging ${#files[@]} file(s)..."

  for file in "${files[@]}"; do
    [[ -f $file ]] && git add "$file" && staged+=("$file") && success "Staged: $file"
  done

  ((${#staged[@]} == 0)) && {
    warn "No files were staged"
    return
  }

  if [[ $auto_commit == "true" ]]; then
    [[ -z $message ]] && {
      file_list=$(printf '%s\n' "${staged[@]}" | sed 's/^/- /')
      message="Add fetched files from GitHub
Files:
$file_list
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
    }
    log "Committing changes..."
    if git commit -m "$message"; then
      success "Committed ${#staged[@]} file(s)"
    else
      warn "Commit failed (no changes or other error)"
    fi
  else
    log "Files staged. Run 'git commit' when ready."
  fi
}

usage() {
  cat <<'EOF'
Usage: git-fetch [MODE] <repo> <paths...> [OPTIONS]

Modes:
  download    Download files to local directory (default)
  add         Download and add to current git repo

Arguments:
  <repo>      Repository in format 'owner/repo'
  <paths>     File/folder paths to fetch (space-separated)
  <url>       GitHub URL (alternative to repo + paths)

Options:
  -b, --branch <name>     Branch name (default: repo's default branch)
  -c, --commit <hash>     Commit hash to fetch from
  -o, --output <dir>      Output directory (download mode, default: .)
  -m, --message <msg>     Commit message (add mode with auto-commit)
  --no-commit             Skip auto-commit in add mode
  --force                 Overwrite existing files
  -h, --help              Show this help message

Examples:
  git-fetch owner/repo path/to/file.txt
  git-fetch owner/repo src/ -b develop
  git-fetch https://github.com/owner/repo/tree/main/src
  git-fetch add owner/repo path/to/file.txt
  git-fetch add owner/repo src/ -m "feat: Add upstream files"
  git-fetch owner/repo src/ -o ./vendor
  git-fetch owner/repo file.txt --force

EOF
  exit 0
}

main() {
  [[ ${1:-} == "-h" || ${1:-} == "--help" ]] && usage

  local mode="download" repo="" branch="" commit="" output_dir="." force="false"
  local auto_commit="true" commit_msg="" token files ref is_folder temp_dir src dest file
  local -a paths=() all_files=()

  [[ ${1:-} =~ ^(download|add)$ ]] && {
    mode="$1"
    shift
  }

  if [[ $# -gt 0 && $1 =~ ^https://github\.com/ ]]; then
    parse_github_url "$1" || die "Invalid GitHub URL format. Expected: https://github.com/owner/repo/(tree|blob)/branch/path"
    repo="$PARSED_REPO"
    branch="$PARSED_BRANCH"
    paths=("$PARSED_PATH")
    shift
    [[ $PARSED_IS_FOLDER == "true" ]] && {
      token=$(get_github_token)
      mapfile -t files < <(collect_folder_files "$repo" "$branch" "$PARSED_PATH")
      paths=("${files[@]}")
    }
  else
    repo="${1:-}"
    [[ -z $repo ]] && usage
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -h | --help) usage ;;
        -b | --branch)
          branch="$2"
          shift 2
          ;;
        -c | --commit)
          commit="$2"
          shift 2
          ;;
        -o | --output)
          output_dir="$2"
          shift 2
          ;;
        -m | --message)
          commit_msg="$2"
          shift 2
          ;;
        --no-commit)
          auto_commit="false"
          shift
          ;;
        --force)
          force="true"
          shift
          ;;
        -*) die "Unknown option: $1. Use -h for help." ;;
        *)
          paths+=("$1")
          shift
          ;;
      esac
    done
  fi

  [[ -z $repo ]] && die "Repository required. Usage: git-fetch <repo> <paths...>"
  ((${#paths[@]} == 0)) && die "No paths specified. Provide at least one file or folder path."
  [[ $repo =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9._-]+$ ]] || die "Invalid repository format. Expected: owner/repo"

  ref=$(resolve_ref "$repo" "$branch" "$commit")
  token=$(get_github_token)
  log "Repository: $repo"
  log "Reference: $ref"
  log "Mode: $mode"

  for path in "${paths[@]}"; do
    is_folder=false
    [[ $path =~ /$ ]] ||
      gh api "repos/$repo/git/trees/$ref?recursive=1" --jq '.tree[] | select(.type == "tree") | .path' 2>/dev/null |
      grep -q "^${path}$" && is_folder=true
    [[ $is_folder == true ]] && {
      mapfile -t files < <(collect_folder_files "$repo" "$ref" "$path")
      all_files+=("${files[@]}")
    } || all_files+=("$path")
  done

  [[ ${#all_files[@]} -eq 0 ]] && die "No files found to download"

  case "$mode" in
    download)
      download_files "$repo" "$ref" "$token" "$force" "$output_dir" "${all_files[@]}"
      success "Downloaded to: $output_dir"
      ;;
    add)
      temp_dir=$(mktemp -d)
      trap 'rm -rf "$temp_dir"' EXIT
      download_files "$repo" "$ref" "$token" "$force" "$temp_dir" "${all_files[@]}"
      log "Moving files to current directory..."
      for file in "${all_files[@]}"; do
        src="$temp_dir/$file"
        dest="./$file"
        [[ -f $src ]] && {
          mkdir -p "$(dirname "$dest")"
          mv "$src" "$dest"
        }
      done
      add_to_repo "$auto_commit" "$commit_msg" "${all_files[@]}"
      ;;
    *) die "Unknown mode: $mode" ;;
  esac
}

main "$@"
