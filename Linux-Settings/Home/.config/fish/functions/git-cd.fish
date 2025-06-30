# Git clone and cd into the repo
function git-cd
    if test (count $argv) -eq 0
        echo "Usage: git-cd <git-repo-url>"
        return 1
    end

    set url $argv[1]

    if type -q gix
        gix clone $url
    else
        git clone $url
    end

    or return 1  # Abort if clone failed

    # Strip trailing slashes and .git suffix
    set repo (basename (string replace --regex -- '(/|\.git)+$' '' $url))
    cd $repo
end
