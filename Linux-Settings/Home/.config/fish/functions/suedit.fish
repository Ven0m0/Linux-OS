function suedit --description 'Edit a file as root using $EDITOR'
    if test -z "$EDITOR"
        echo "❌ \$EDITOR is not set. Please set your editor first." >&2
        return 1
    end

    if type -q sudo-rs    
        sudo-rs $EDITOR $argv
    else if type -q doas
        doas $EDITOR $argv
    else
        sudo $EDITOR $argv
    end
end
