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
success(){ printf "${GRN}✓ %s${DEF}\n" "$*"; }
warn(){ printf "${YLW}⚠ %s${DEF}\n" "$*" >&2; }
err(){ printf "${RED}ERROR: %s${DEF}\n" "$*" >&2; }
die(){ err "$*"; exit 1; }

# Dependencies
has gh  || die "Missing dependency: gh"
has curl || die "Missing dependency: curl"
has jq  || die "Missing dependency: jq"

# URL-encode a filename (no subshell echo — printf is a builtin)
urlencode_filename(){
  printf '%s' "$*" | sed \
    -e 's/%/%25/g' -e 's/ /%20/g' -e 's/!/%21/g' -e 's/"/%22/g' -e "s/'/%27/g" \
    -e 's/#/%23/g' -e 's/(/%28/g' -e 's/)/%29/g' -e 's/+/%2b/g' -e 's/,/%2c/g' \
    -e 's/:/%3a/g' -e 's/;/%3b/g' -e 's/?/%3f/g' -e 's/@/%40/g' -e 's/\$/%24/g' \
    -e 's/\&/%26/g' -e 's/\*/%2a/g' -e 's/\./%2e/g' -e 's/\//%2f/g' \
    -e 's/\[/%5b/g' -e 's/\\/%5c/g' -e 's/\]/%5d/g' -e 's/\^/%5e/g' \
    -e 's/_/%5f/g' -e 's/`/%60/g' -e 's/{/%7b/g' -e 's/|/%7c/g' \
    -e 's/}/%7d/g' -e 's/~/%7e/g'
}

# Parse a GitHub URL, set PARSED_* globals
# Sets: PARSED_REPO PARSED_BRANCH PARSED_PATH PARSED_IS_FOLDER
parse_github_url(){
  local url=$1
  local regex='^https://github\.com/([A-Za-z0-9_-]+)/([A-Za-z0-9._-]+)/(tree|blob)/([A-Za-z0-9._/-]+)/(.+)$'
  [[ $url =~ $regex ]] || return 1
  declare -g PARSED_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  declare -g PARSED_BRANCH="${BASH_REMATCH[4]}"
  declare -g PARSED_PATH="${BASH_REMATCH[5]}"
  if [[ ${BASH_REMATCH[3]} == "tree" ]]; then
    declare -g PARSED_IS_FOLDER="true"
  else
    declare -g PARSED_IS_FOLDER="false"
  fi
}

# Resolve git ref: commit > branch > repo default > "main"
resolve_ref(){
  local repo=$1 branch=${2:-} commit=${3:-}
  if [[ -n $commit ]]; then
    printf '%s' "$commit"
  elif [[ -n $branch ]]; then
    printf '%s' "$branch"
  else
    gh api "repos/$repo" --jq '.default_branch' 2>/dev/null || printf 'main'
  fi
}

# Get GitHub auth token from env or gh CLI
get_github_token(){
  local token=${GITHUB_TOKEN:-}
  if [[ -z $token ]]; then
    token=$(gh auth token -h github.com 2>/dev/null) || die "No GitHub token. Run: gh auth login"
  fi
  printf '%s' "$token"
}

# List all blob paths under a folder in a repo tree
collect_folder_files(){
  local repo=$1 branch=$2 folder=$3
  log "Collecting files from folder: $folder"
  gh api "repos/$repo/git/trees/$branch?recursive=1" \
    --jq '.tree[] | select(.type == "blob") | .path' 2>/dev/null \
    | grep -E "^${folder}(/|$)" \
    || die "Failed to fetch folder contents for $repo@$branch"
}

# Download files to output_dir in parallel via curl
download_files(){
  local repo=$1 branch=$2 token=$3 force=$4 output_dir=$5
  shift 5
  local -a paths=("$@") curl_args=() skipped=() downloaded=()
  local dest encoded_path file

  for file in "${paths[@]}"; do
    dest="$output_dir/$file"
    if [[ -f $dest && $force != "true" ]]; then
      skipped+=("$file")
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    encoded_path=$(urlencode_filename "$file")
    curl_args+=("https://raw.githubusercontent.com/$repo/$branch/$encoded_path" "-o" "$dest")
    downloaded+=("$file")
  done

  if (( ${#skipped[@]} > 0 )); then
    warn "Skipped ${#skipped[@]} existing file(s) (use --force to overwrite):"
    printf '  %s\n' "${skipped[@]}" >&2
  fi

  if (( ${#curl_args[@]} == 0 )); then
    return
  fi

  log "Downloading ${#downloaded[@]} file(s)..."
  curl --location --create-dirs --parallel --parallel-max 32 \
    --retry 3 --retry-delay 1 --oauth2-bearer "$token" \
    "${curl_args[@]}" 2>/dev/null \
    || die "Download failed. Check network connection and permissions."

  for file in "${downloaded[@]}"; do
    success "$file"
  done
}

# Stage downloaded files; optionally auto-commit
add_to_repo(){
  local auto_commit=$1 message=$2
  shift 2
  local -a files=("$@") staged=()
  local file file_list

  git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository. Run: git init"
  log "Staging ${#files[@]} file(s)..."

  for file in "${files[@]}"; do
    if [[ -f $file ]]; then
      git add "$file"
      staged+=("$file")
      success "Staged: $file"
    fi
  done

  if (( ${#staged[@]} == 0 )); then
    warn "No files were staged"
    return
  fi

  if [[ $auto_commit == "true" ]]; then
    if [[ -z $message ]]; then
      file_list=$(printf '  - %s\n' "${staged[@]}")
      message="feat: add fetched files from GitHub

Files:
$file_list"
    fi
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

usage(){
  cat <<'EOF'
Usage: git-fetch [MODE] <repo|url> [paths...] [OPTIONS]

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
  --version               Show version

Examples:
  git-fetch owner/repo path/to/file.txt
  git-fetch owner/repo src/ -b develop
  git-fetch https://github.com/owner/repo/tree/main/src
  git-fetch add owner/repo path/to/file.txt
  git-fetch add owner/repo src/ -m "feat: add upstream files"
  git-fetch owner/repo src/ -o ./vendor
  git-fetch owner/repo file.txt --force
EOF
  exit 0
}

main(){
  [[ ${1:-} == "-h" || ${1:-} == "--help" ]] && usage
  [[ ${1:-} == "--version" ]] && { printf 'git-fetch 2.0.0\n'; exit 0; }

  local mode="download" repo="" branch="" commit="" output_dir="." force="false"
  local auto_commit="true" commit_msg="" token ref is_folder temp_dir src dest file
  local -a paths=() all_files=()

  # Optional mode prefix
  if [[ ${1:-} =~ ^(download|add)$ ]]; then
    mode=$1
    shift
  fi

  # GitHub URL shorthand
  if [[ $# -gt 0 && $1 =~ ^https://github\.com/ ]]; then
    parse_github_url "$1" \
      || die "Invalid GitHub URL. Expected: https://github.com/owner/repo/(tree|blob)/branch/path"
    repo=$PARSED_REPO
    branch=$PARSED_BRANCH
    paths=("$PARSED_PATH")
    shift
    if [[ $PARSED_IS_FOLDER == "true" ]]; then
      token=$(get_github_token)
      mapfile -t all_files < <(collect_folder_files "$repo" "$branch" "$PARSED_PATH")
    fi
  else
    repo=${1:-}
    [[ -z $repo ]] && usage
    shift

    while (( $# )); do
      case $1 in
        -h|--help) usage;;
        --version) printf 'git-fetch 2.0.0\n'; exit 0;;
        -b|--branch) branch=${2:?missing branch name}; shift 2;;
        -c|--commit) commit=${2:?missing commit hash}; shift 2;;
        -o|--output) output_dir=${2:?missing output dir}; shift 2;;
        -m|--message) commit_msg=${2:?missing commit message}; shift 2;;
        --no-commit) auto_commit="false"; shift;;
        --force) force="true"; shift;;
        -*) die "Unknown option: $1. Use -h for help.";;
        *) paths+=("$1"); shift;;
      esac
    done
  fi

  [[ -z $repo ]] && die "Repository required. Usage: git-fetch <repo> <paths...>"
  [[ $repo =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9._-]+$ ]] \
    || die "Invalid repository format. Expected: owner/repo"
  (( ${#paths[@]} > 0 || ${#all_files[@]} > 0 )) \
    || die "No paths specified. Provide at least one file or folder path."

  ref=$(resolve_ref "$repo" "$branch" "$commit")
  token=$(get_github_token)
  log "Repository: $repo"
  log "Reference:  $ref"
  log "Mode:       $mode"

  # Expand any folder paths if not already populated from URL
  if (( ${#all_files[@]} == 0 )); then
    for path in "${paths[@]}"; do
      # A path is a folder if it ends in / or matches a tree entry in the API
      if [[ $path =~ /$ ]]; then
        is_folder=true
      else
        is_folder=false
        if gh api "repos/$repo/git/trees/$ref?recursive=1" \
            --jq '.tree[] | select(.type == "tree") | .path' 2>/dev/null \
            | grep -q "^${path}$"; then
          is_folder=true
        fi
      fi

      if [[ $is_folder == true ]]; then
        mapfile -t files < <(collect_folder_files "$repo" "$ref" "${path%/}")
        all_files+=("${files[@]}")
      else
        all_files+=("$path")
      fi
    done
  fi

  (( ${#all_files[@]} > 0 )) || die "No files found to download"

  case $mode in
    download)
      download_files "$repo" "$ref" "$token" "$force" "$output_dir" "${all_files[@]}"
      success "Downloaded to: $output_dir"
      ;;
    add)
      temp_dir=$(mktemp -d)
      trap 'rm -rf "$temp_dir"' EXIT
      download_files "$repo" "$ref" "$token" "$force" "$temp_dir" "${all_files[@]}"
      log "Moving files to working directory..."
      for file in "${all_files[@]}"; do
        src="$temp_dir/$file"
        dest="./$file"
        if [[ -f $src ]]; then
          mkdir -p "$(dirname "$dest")"
          mv "$src" "$dest"
        fi
      done
      add_to_repo "$auto_commit" "$commit_msg" "${all_files[@]}"
      ;;
    *) die "Unknown mode: $mode";;
  esac
}

main "$@"
