#!/usr/bin/env bash

##==================================================================================================
##	Requirements
##==================================================================================================

has() { command -v $1 &>/dev/null || { echo "Aborting: '$1' not found"; exit 1; }; }
has git


##==================================================================================================
##	Helper functions
##==================================================================================================

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
        git -C "$dir" remote prune origin

        ## Optimize, if needed
        git -C "$dir" gc --auto --aggressive
    fi
}


##==================================================================================================
##	Main script
##==================================================================================================

for dir in $(getGitDirs $1) ; do
    housekeepGirDir $dir
done
wait
