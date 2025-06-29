function gc
    if test (count $argv) -eq 0
        echo "Usage: gc <git-repo-url>"
        return 1
    end

    set url $argv[1]

    if type -q gix
        gix clone $url
    else
        git clone $url
    end

    or return 1  # Abort if clone failed

    # Strip trailing slash and .git suffix
    set repo (basename (string trim --right --chars=/ $url) .git)
    cd $repo
end
