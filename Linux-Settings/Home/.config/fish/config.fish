source /usr/share/cachyos-fish-config/cachyos-config.fish

if test -d ~/.basher
    set basher ~/.basher/bin
end
set -gx PATH $basher $PATH
status --is-interactive; and . (basher init - fish | psub)
starship init fish | source
