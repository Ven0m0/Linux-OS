source /usr/share/cachyos-fish-config/cachyos-config.fish

if test -d ~/.basher
    set basher ~/.basher/bin
end
set -gx PATH $basher $PATH
status --is-interactive; and . (basher init - fish | psub)

# Prompt
#starship init fish | source
#pay-respects fish --alias | source
#zoxide init fish | source
#fzf --fish | source

_evalcache starship init fish
if type -q batman
	_evalcache batman --export-env
end
if type -q zoxide
	#zoxide init fish | source
	_evalcache zoxide init fish
end
if type -q pay-respects
	#pay-respects fish --alias | source
	_evalcache pay-respects fish --alias
end

_evalcache fzf --fish

#_evalcache starship init fish
#_evalcache batman --export-env
#_evalcache pay-respects fish --alias
#_evalcache zoxide init fish

# Async prompt
set -U async_prompt_functions fish_prompt fish_right_prompt
set -gx async_prompt_enable 1
