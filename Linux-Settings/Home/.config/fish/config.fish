source /usr/share/cachyos-fish-config/cachyos-config.fish

if test -d ~/.basher
    set basher ~/.basher/bin
end
set -gx PATH $basher $PATH
status --is-interactive; and . (basher init - fish | psub)

# Fix weird fish binding, restore ctrl+v
bind --erase \cv

# Prompt
# _evalcache fzf --fish
#_evalcache zoxide init fish

_evalcache starship init fish
if type -q batman
	_evalcache batman --export-env
end
if type -q batpipe
	_evalcache batpipe
end
if type -q pay-respects
	_evalcache pay-respects fish --alias
end

# ─── Ghostty bash integration ─────────────────────────────────────────────────────────
if test "$TERM" = "xterm-ghostty" -a -e "$GHOSTTY_RESOURCES_DIR"/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
    source "$GHOSTTY_RESOURCES_DIR"/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
end

set -U FZF_LEGACY_KEYBINDINGS 0
set -U FZF_COMPLETE 1
bind \cs '__ethp_commandline_toggle_sudo.fish'
# Async prompt
set -U async_prompt_functions fish_prompt fish_right_prompt
set -gx async_prompt_enable 1
set -gx FORGIT_INSTALL_DIR "/usr/share/fish/vendor_conf.d"
