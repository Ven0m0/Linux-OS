source /usr/share/cachyos-fish-config/cachyos-config.fish
# source ~/.config/fish/conf.d/ven0m0.fish

if test -d ~/.basher
    set basher ~/.basher/bin
end
set -gx PATH $basher $PATH
status --is-interactive; and . (basher init - fish | psub)
# Prompt
starship init fish | source
pay-respects fish --alias | source
