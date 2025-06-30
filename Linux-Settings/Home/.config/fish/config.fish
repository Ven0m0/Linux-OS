source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting, potentially disabling fastfetch
function fish_greeting
        crabfetch -d arch || fastfetch
end
if test -d ~/.basher          ##basher5ea843
  set basher ~/.basher/bin    ##basher5ea843
end                           ##basher5ea843
set -gx PATH $basher $PATH    ##basher5ea843
status --is-interactive; and . (basher init - fish | psub)    ##basher5ea843

set -x XDG_CONFIG_HOME $HOME/.config
set -x XDG_CACHE_HOME  $HOME/.cache
set -x XDG_DATA_HOME   $HOME/.local/share
set -x XDG_STATE_HOME  $HOME/.local/state
