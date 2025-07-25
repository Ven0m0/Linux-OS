source /usr/share/cachyos-fish-config/cachyos-config.fish

if test -d ~/.basher
    set basher ~/.basher/bin
end
set -gx PATH $basher $PATH
status --is-interactive; and . (basher init - fish | psub)

# Fix weird fish binding, restore ctrl+v
bind --erase \cv

# Prompt
#starship init fish | source
#pay-respects fish --alias | source
#zoxide init fish | source
#fzf --fish | source

_evalcache starship init fish
if type -q batman
	_evalcache batman --export-env
end
if type -q batpipe
	_evalcache batpipe
end
if type -q zoxide
	_evalcache zoxide init fish
end
if type -q pay-respects
	#pay-respects fish --alias | source
	_evalcache pay-respects fish --alias
end
if type -q fzf
	_evalcache fzf --fish
fi

# ─── Ghostty bash integration ─────────────────────────────────────────────────────────
if test "$TERM" = "xterm-ghostty" -a -e "$GHOSTTY_RESOURCES_DIR"/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
    source "$GHOSTTY_RESOURCES_DIR"/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
end

# Async prompt
set -U async_prompt_functions fish_prompt fish_right_prompt
set -gx async_prompt_enable 1
