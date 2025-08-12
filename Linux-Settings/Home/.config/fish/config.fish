source /usr/share/cachyos-fish-config/cachyos-config.fish

set -gx fish_prompt_pwd_dir_length 2
set -gx __fish_git_prompt_show_informative_status 0
set -gx __fish_git_prompt_showupstream none
function fish_title
end
# Run welcome message
if type -q hyfetch >/dev/null 2>&1
    set fetch hyfetch -b fastfetch -m rgb -p transgender
else if type -q fastfetch >/dev/null 2>&1
    set fetch fastfetch --detect-version false --users-myself-only --localip-compact --ds-force-drm --thread
end
function fish_greeting
    LC_ALL=C $fetch 2>/dev/null
end

if test -d ~/.basher
    set basher ~/.basher/bin
end
set -gx PATH $basher $PATH
status --is-interactive; and . (basher init - fish | psub)

set -e LC_ALL

# Fix weird fish binding, restore ctrl+v
bind --erase \cv 2>/dev/null

# Prompt
_evalcache starship init fish 2>/dev/null

if type -q batman >/dev/null 2>&1
	_evalcache batman --export-env 2>/dev/null
end
if type -q batpipe >/dev/null 2>&1
	_evalcache batpipe 2>/dev/null
end
if type -q pay-respects >/dev/null 2>&1
	_evalcache pay-respects fish --alias 2>/dev/null
end

# ─── Ghostty bash integration ─────────────────────────────────────────────────────────
if test "$TERM" = "xterm-ghostty" -a -e "$GHOSTTY_RESOURCES_DIR"/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
    source "$GHOSTTY_RESOURCES_DIR"/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
end
set -gx FZF_LEGACY_KEYBINDINGS 0 2>/dev/null
set -gx FZF_COMPLETE 1 2>/dev/null
bind \cs '__ethp_commandline_toggle_sudo.fish' 2>/dev/null
# Async prompt
set -U async_prompt_functions fish_prompt fish_right_prompt
set -gx async_prompt_enable 1

 _evalcache fzf --fish 2>/dev/null
if type -q zoxide >/dev/null 2>&1
	set _ZO_FZF_OPTS "--info=inline --tiebreak=index --layout=reverse-list --select-1 --exit-0"
	_evalcache zoxide init fish 2>/dev/null
end

# ─── Abbreviations ─────────────────────────────────────────────────────────
abbr -a
abbr -a mv mv -iv
abbr -a rm rm -iv
abbr -a cp cp -iv
abbr -a sort sort -h
abbr -a mkdir mkdir -pv
abbr -a df df -h
abbr -a free free -h
#abbr -a grep grep -n
abbr -a ip ip --color=auto
abbr -a du du -hcsx
