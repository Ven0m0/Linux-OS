function suedit --description 'Edit a file as root using $EDITOR'
    doas $EDITOR $argv
end
