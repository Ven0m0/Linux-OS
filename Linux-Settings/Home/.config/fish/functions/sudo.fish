function sudo --wraps='pkexec --keep-cwd' --wraps=doas --description 'alias sudo=doas'
    doas $argv
end

function sudo --description 'Use doas if available, fallback to sudo'
    if type -q doas
        command doas $argv
    else
        command sudo $argv
    end
end
