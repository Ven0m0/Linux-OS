source /usr/share/cachyos-fish-config/cachyos-config.fish

set -gx fish_prompt_pwd_dir_length 2
set -gx __fish_git_prompt_show_informative_status 0
set -gx __fish_git_prompt_showupstream none
set -gx fish_term24bit 1
function fish_title
end

set -l stealth 1

# choose fetch command depending on stealth and available tools
if test "$stealth" = "1"
  if type -q fastfetch
    set -g fetch 'fastfetch --detect-version false --users-myself-only --localip-compact --ds-force-drm --thread'
  else
    set -e fetch
  end
else if type -q hyfetch
  set -g fetch 'hyfetch -b fastfetch -m rgb -p transgender'
else if type -q fastfetch
  set -g fetch 'fastfetch --detect-version false --users-myself-only --localip-compact --ds-force-drm --thread'
else
  set -e fetch
end
# greeting runs the chosen fetch if present
function fish_greeting
  if set -q fetch
    LC_ALL=C LANG=C eval $fetch 2>/dev/null
  end
end

# If stealth, try to disable mommy (plugin defines __call_mommy --on-event fish_postexec)
if test "$stealth" = "1"
  # remove it now if already defined
  if functions -q __call_mommy
    functions -e __call_mommy
  end
  # one-shot watcher: if mommy appears later, erase it and then remove this watcher
  function __disable_mommy --on-event fish_postexec
    if functions -q __call_mommy
      functions -e __call_mommy
    end
    functions -e __disable_mommy
  end
end

if test -d ~/.basher
    set basher ~/.basher/bin
end
set -gx PATH $basher $PATH
# status --is-interactive >/dev/null 2>&1; and source (basher init - fish | psub)
status --is-interactive >/dev/null 2>&1; and _evalcache basher init - fish 2>/dev/null

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
abbr -a mv mv -iv
abbr -a rm rm -iv
abbr -a cp cp -iv
abbr -a sort sort -h
abbr -a mkdir mkdir -pv
abbr -a df df -h
abbr -a free free -h
abbr -a ip ip --color=auto
abbr -a du du -hcsx

true >/dev/null 2>&1
