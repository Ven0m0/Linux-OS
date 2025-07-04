function suedit --description 'Edit a file as root using $EDITOR'
    if test -z "$EDITOR"
        echo "❌ \$EDITOR is not set. Please set your editor first." >&2
        return 1
    end

    if type -q sudo-rs    
        sudo-rs $EDITOR $argv[1]
    else if type -q doas
        doas $EDITOR $argv[1]
    else
        sudo $EDITOR $argv[1]
    end
end
