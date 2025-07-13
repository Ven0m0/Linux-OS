source /usr/share/cachyos-fish-config/cachyos-config.fish

if test -d ~/.basher
    set basher ~/.basher/bin
end
set -gx PATH $basher $PATH
status --is-interactive; and . (basher init - fish | psub)

# Prompt
starship init fish | source
pay-respects fish --alias | source
zoxide init fish | source
fzf --fish | source
# Async prompt
set -U async_prompt_functions fish_prompt fish_right_prompt
set -gx async_prompt_enable 1
# you see nothing stranger...
set -gx SHELL_MOMMYS_ONLY_NEGATIVE true
