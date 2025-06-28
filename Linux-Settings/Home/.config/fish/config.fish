source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting, potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end
if test -d ~/.basher          ##basher5ea843
  set basher ~/.basher/bin    ##basher5ea843
end                           ##basher5ea843
set -gx PATH $basher $PATH    ##basher5ea843
status --is-interactive; and . (basher init - fish | psub)    ##basher5ea843
source ~/.config/fish/conf.d/ven0m0.fish
