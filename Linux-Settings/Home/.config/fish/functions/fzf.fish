function fzf -d "Lazy-load fzf integration"
    functions -e fzf
    fzf --fish | source
    commandline -f repaint
    fzf $argv
end
