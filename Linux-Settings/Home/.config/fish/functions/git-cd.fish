function gitctl
    if test (count $argv) -eq 0
        echo "Usage: gitctl <git-repo-url> [directory]"
        return 1
    end

    set url $argv[1]
    set dir ""

    # Use provided directory name or derive from URL
    if test (count $argv) -ge 2
        set dir $argv[2]
    else
        # Strip trailing slashes and .git suffix
        set base (string replace --regex -- '(/|\.git)+$' '' $url)
        set dir (basename $base)
    end

    # If directory already exists, just cd into it
    if test -d $dir
        cd $dir
        return 0
    end

    # Clone with gix if available, otherwise git
    if type -q gix
        gix clone $url $dir
    else
        git clone $url $dir
    end

    or return 1  # Abort if clone failed

    cd $dir
end
