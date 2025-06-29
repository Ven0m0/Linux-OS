function edit --wraps='$EDITOR' --description 'alias edit $EDITOR'
  $EDITOR $argv
end

function suedit --description 'Edit a file as root using $EDITOR'
    sudo $EDITOR $argv
end
