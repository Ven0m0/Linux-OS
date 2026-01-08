#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

readonly CLI="gh-unified"
readonly VERSION="1.0.0"
has(){ command -v -- "$1" &>/dev/null; }
msg(){ printf '%s\n' "$@"; }
log(){ printf '%s\n' "$@" >&2; }
die(){ printf '%s\n' "$1" >&2; exit "${2:-1}"; }

usage(){
  cat <<EOF
Usage: $CLI <repo> [<... paths>]
       $CLI <url>
       $CLI install <repo>

Modes:
  install <repo>       Download & install binary from GitHub releases
  <repo> <... paths>    Download folders/files without cloning
  <url>                Download from GitHub tree/blob URL

Arguments:
  <repo>               username/repo (defaults to gh user if username missing)
  <...paths>           folder or file paths
  <url>                https://github.com/...

Options:
  -h, --help           Show usage
  -v, --version        Show version
  --verbose            Enable debug
  -d, --dry-run        Report downloads without executing
  -b, --branch <name>  Branch or tag (default: default branch)
  --outdir <path>      Output directory (single path only)
  --outfile <path>     Output file (single file only)

Examples:
  $CLI install cli/cli
  $CLI yuler/gh-download README.md gh-download
  $CLI cli/cli .github
  $CLI https://github.com/yuler/actions/tree/main/ci
EOF
  exit 0
}
version_print(){ echo "$CLI v$VERSION"; exit 0; }
urlencode_filename(){
  printf '%s\n' "$*" | sed \
    -e 's/%/%25/g' -e 's/ /%20/g' -e 's/! /%21/g' -e 's/"/%22/g' \
    -e "s/'/%27/g" -e 's/#/%23/g' -e 's/(/%28/g' -e 's/)/%29/g' \
    -e 's/+/%2b/g' -e 's/,/%2c/g' -e 's/-/%2d/g' -e 's/:/%3a/g' \
    -e 's/;/%3b/g' -e 's/?/%3f/g' -e 's/@/%40/g' -e 's/\$/%24/g' \
    -e 's/\&/%26/g' -e 's/\*/%2a/g' -e 's/\. /%2e/g' -e 's/\//%2f/g' \
    -e 's/\[/%5b/g' -e 's/\\/%5c/g' -e 's/\]/%5d/g' -e 's/\^/%5e/g' \
    -e 's/_/%5f/g' -e 's/`/%60/g' -e 's/{/%7b/g' -e 's/|/%7c/g' \
    -e 's/}/%7d/g' -e 's/~/%7e/g'
}
choose(){
  [[ $# -eq 0 ]] && die "choose:  no options"
  if has fzf; then
    printf '%s\n' "$@" | fzf --height=10 --prompt="${PS3}" -1
  else
    select opt in "$@"; do
      [[ -n $opt ]] && { echo "$opt"; break; }
    done
  fi
}
extract(){
  local f=$1
  [[ !  -f $f ]] && { log "'$f' not a file"; return 1; }
  case $f in
    *.tar.bz2|*.tbz2) tar xjf "$f";;
    *.tar.gz|*.tgz)   tar xzf "$f";;
    *.tar.xz)         tar xf "$f";;
    *.tar.zst)        tar xf "$f";;
    *.bz2)            bunzip2 "$f";;
    *.gz)             gunzip "$f";;
    *.tar)            tar xf "$f";;
    *. zip)            unzip -q "$f";;
    *.Z)              uncompress "$f";;
    *) log "'$f' cannot be extracted; assuming binary"; return 1;;
  esac
  return 0
}
# ──────────────────────────────────────────────────────────────────────────────
# Install mode: download release binary
# ──────────────────────────────────────────────────────────────────────────────
do_install(){
  local repo=$1
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/gh-install.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  local binpath="${GH_BINPATH:-$HOME/.local/bin}"
  log "[repo] $repo"
  PS3="> Select version: "
  local tag
  mapfile -t tags < <(gh api "repos/$repo/releases" --jq '.[].tag_name')
  [[ ${#tags[@]} -eq 0 ]] && die "No releases found"
  tag=$(choose "${tags[@]}")
  log "[version] $tag"
  PS3="> Select file: "
  local filename
  mapfile -t files < <(gh api "repos/$repo/releases" \
    --jq ". [] | select(.tag_name == \"$tag\") | .assets[].name")
  [[ ${#files[@]} -eq 0 ]] && die "No assets found for $tag"
  filename=$(choose "${files[@]}")
  log "[filename] $filename"
  log "[*] Downloading $filename..."
  gh release download "$tag" --repo "$repo" --pattern "$filename" --dir "$tmp"
  cd "$tmp"
  if [[ $filename == *.deb ]]; then
    log "[*] Installing debian package..."
    sudo apt install ". /$filename"
    return
  fi
  log "[*] Extracting..."
  local bin
  if extract "$filename"; then
    PS3="> Select binary: "
    mapfile -t bins < <(find .  -type f !  -name "$filename" -printf '%P\n')
    [[ ${#bins[@]} -eq 0 ]] && die "No binaries found in archive"
    bin=$(choose "${bins[@]}")
  else
    bin=$filename
  fi
  local basename="${bin##*/}"
  read -rp "> Choose name (empty=$basename): " name
  mkdir -p "$binpath"
  local target="$binpath/${name:-$basename}"
  mv "$bin" "$target"
  chmod +x "$target"
  msg "Success!  Saved in: $target"
}

# ──────────────────────────────────────────────────────────────────────────────
# Download mode: download files/folders from repo
# ──────────────────────────────────────────────────────────────────────────────
declare -a URLS=()
declare repo branch outdir outfile dry_run token
collection_file(){
  local file=$1 folder=${2:-} dest=${3:-}
  [[ -z $folder ]] && folder=$(dirname "$file")
  if [[ -z $dest && -n $outdir && -n $folder ]]; then
    [[ $folder == "." ]] && dest="$outdir/$file" || dest="${file/$folder/$outdir}"
  fi
  [[ -n $outfile ]] && dest=$outfile
  [[ -z $dest ]] && dest=$file
  log "Collection file: \`$file\` → \`$dest\`"
  URLS+=("https://raw.githubusercontent.com/$repo/$branch/$(urlencode_filename "$file")" "$dest")
}

collection_folder(){
  local folder=$1
  log "Collection folder: \`$folder\`..."
  local files
  mapfile -t files < <(gh api "repos/$repo/git/trees/$branch?recursive=1" \
    --jq ".tree[] | select(.type == \"blob\") | .path | select(startswith(\"$folder/\"))")
  for f in "${files[@]}"; do
    collection_file "$f" "$folder"
  done
}

download_parallel(){
  [[ ${#URLS[@]} -eq 0 ]] && { log "No files to download"; return; }
  local args=(--location --create-dirs --oauth2-bearer "$token" --parallel-immediate --parallel)
  for ((i=0; i<${#URLS[@]}; i+=2)); do
    args+=(--url "${URLS[i]}" --output "${URLS[i+1]}")
  done
  if [[ ${dry_run:-} == true ]]; then
    log "[dry-run] curl ${args[*]}"
  else
    curl "${args[@]}"
  fi
}

do_download(){
  token=$(gh auth token -h github.com)

  local url_regex='^https://github.com/([A-Za-z0-9_-]+)/([A-Za-z0-9._-]+)/(tree|blob)/([A-Za-z0-9._/-]+)/(.*)$'
  if [[ $# -eq 1 && $1 =~ $url_regex ]]; then
    repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    branch="${BASH_REMATCH[4]}"
    local path="${BASH_REMATCH[5]}"
    log "[repo] $repo"
    log "[branch] $branch"
    case "${BASH_REMATCH[3]}" in
      tree) collection_folder "$path";;
      blob) collection_file "$path";;
    esac
    download_parallel
    return
  fi
  repo=$1; shift
  if [[ !  $repo =~ / ]]; then
    local username
    username=$(gh config get -h github.com user)
    repo="$username/$repo"
  fi
  [[ -z ${branch:-} ]] && branch=$(gh api "repos/$repo" --jq . default_branch)
  log "[repo] $repo"
  log "[branch] $branch"

  if [[ $# -eq 1 ]]; then
    local path=$1
    local folder
    [[ $path =~ /$ ]] && folder="${path%/}" || \
      folder=$(gh api "repos/$repo/git/trees/$branch?recursive=1" \
        --jq ".tree[] | select(.type == \"tree\") | .path | select(.==\"$path\")")

    if [[ -n $folder ]]; then
      collection_folder "$folder"
    else
      collection_file "$path"
    fi
    download_parallel
    return
  fi
  unset outfile outdir
  for path in "$@"; do
    local folder
    [[ $path =~ /$ ]] && folder="${path%/}" || \
      folder=$(gh api "repos/$repo/git/trees/$branch?recursive=1" \
        --jq ".tree[] | select(.type == \"tree\") | .path | select(.==\"$path\")")

    if [[ -n $folder ]]; then
      collection_folder "$folder"
    else
      collection_file "$path"
    fi
  done
  download_parallel
}
# ──────────────────────────────────────────────────────────────────────────────
# Main argument parsing
# ──────────���───────────────────────────────────────────────────────────────────
main(){
  [[ $# -eq 0 ]] && usage
  local -a POSITIONAL=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)    usage;;
      -v|--version) version_print;;
      --verbose)    set -x; shift;;
      -d|--dry-run) dry_run=true; shift;;
      -b|--branch)  branch=$2; shift 2;;
      --outdir)     outdir=$2; shift 2;;
      --outfile)    outfile=$2; shift 2;;
      *) POSITIONAL+=("$1"); shift;;
    esac
  done
  set -- "${POSITIONAL[@]}"
  [[ $# -eq 0 ]] && usage
  if [[ $1 == install ]]; then
    shift
    [[ $# -eq 0 ]] && die "install requires <repo>"
    do_install "$1"
  else
    do_download "$@"
  fi
}
main "$@"
