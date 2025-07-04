source /usr/share/cachyos-fish-config/cachyos-config.fish

if test -d ~/.basher          ##basher5ea843
  set basher ~/.basher/bin    ##basher5ea843
end                           ##basher5ea843
set -gx PATH $basher $PATH    ##basher5ea843
status --is-interactive; and . (basher init - fish | psub)    ##basher5ea843

