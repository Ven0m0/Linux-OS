#!/usr/bin/env bash
shopt -s nullglob globstar; set -u
export LC_ALL=C LANG=C.UTF-8
##==================================================================================================
##	Requirements
has() { command -v $1 &>/dev/null || { echo "Aborting: '$1' not found"; exit 1; }; }
has git
##==================================================================================================
##	Helper functions
getGitDirs() {
  find $1 -type d -name .git -not -path "*.local*" | sed 's/\/.git$//g'
}

housekeepGirDir() {
  local dir=$1
  if [ -d "${dir}" -a -d "${dir}/.git" ]; then
    echo -e "\033[1mGit housekeeping: ${dir}\033[0m"
   ## Fetch from remote, twice in case something goes wrong
    git -C "$dir" fetch || git -C "$dir" fetch

    ## Delete local (non-important) branches that have been merged.
    git -C "$dir" branch --merged \
            | grep -E -v "(^\*|HEAD|master|main|dev|release)" \
            | xargs -r git branch -d
    ## Prune origin: stop tracking branches that do not exist in origin
    git -C "$dir" remote prune origin >/dev/null
    ## Optimize, if needed
		git -C "$dir" repack -ad --depth=250 --window=250 --cruft --threads="$(nproc)" >/dev/null
  	git reflog expire --expire=now --all >/dev/null
    git -C "$dir" gc --auto --aggressive --prune=now >/dev/null
    git clean -fdXq >/dev/null
  fi
}

##==================================================================================================
##	Main script
##==================================================================================================
for dir in $(getGitDirs $1) ; do
  housekeepGirDir $dir
done; wait
