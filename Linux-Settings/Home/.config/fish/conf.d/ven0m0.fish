# Run crabfetch/fastfetch as welcome message
function fish_greeting
        crabfetch -d arch || fastfetch
end

# ─── Paths─────────────────────────────────────────────────────────

set -x XDG_CONFIG_HOME $HOME/.config
set -x XDG_CACHE_HOME  $HOME/.cache
set -x XDG_DATA_HOME   $HOME/.local/share
set -x XDG_STATE_HOME  $HOME/.local/state

# ─── Environment Tweaks ─────────────────────────────────────────────────────────
set -gx EDITOR micro
set -gx VISUAL $EDITOR
set -gx SYSTEMD_EDITOR $EDITOR
# set -gx PAGER less
set -x PAGER bat
# set -gx LESS '-RFQXsn --no-histdups --mouse --wheel-lines=4'
set -gx LESSOPEN "|/usr/bin/batpipe %s"
set -gx LESSHISTFILE '-'
set -gx SYSTEMD_LESS $LESS
set -gx BATPIPE "color"

# Avoid expensive VCS prompt delays
set -g __fish_git_prompt_show_informative_status 0
set -g __fish_git_prompt_showupstream none

# Faster locale in for scripts
if not status --is-interactive
  set -x LANG C; set -x LC_ALL C
end

# ─── Only for Interactive Shells ────────────────────────────────────────────────
if status --is-interactive
    # Locale (Fast & Unicode-Compatible)
    #set -x LANG C.UTF-8; set -x LC_ALL C.UTF-8

    # Fast prompt (truncate deep paths)
    set fish_prompt_pwd_dir_length 1

    # Aliases: safe & efficient defaults
    alias cat='bat --strip-ansi=auto --squeeze-blank --style=auto --paging=auto'

    # My stuff
    alias sshdb='dbclient'
    alias ptch='patch -p1 <'
    alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'
    alias clearnsh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'

    # Better sudo (if available)
    #if type -q sudo-rs
        #alias sudo sudo-rs
    #end
    #if type -q su-rs
        #alias su su-rs
    #end

    if type -q rg
      functions -e rg 2>/dev/null # reset due to cachyos-fish-config
      alias rg='rg --no-unicode --no-stats --color=auto -S --engine=auto -j 16 --block-buffered'
      functions -e grep 2>/dev/null
      alias grep='rg -F --no-unicode -uuu --no-stats --color=auto --engine=default -j 16 --block-buffered'
      functions -e fgrep 2>/dev/null
      alias fgrep='rg -uuu --no-stats --color=auto -E UTF-8 -j 16'
      functions -e egrep 2>/dev/null
      alias egrep='rg --no-stats --color=auto'
    else
      alias grep='grep --color=auto'
      alias fgrep='fgrep --color=auto'
      alias egrep='egrep --color=auto'
    end

   # Reset
   function cls
     clear
     fish_greeting
   end

   abbr --add c cls

    # bind Esc Esc to toggle_sudo
    source ~/.config/fish/functions/presudo.fish
    bind \e\e toggle_sudo

    function which
      type $argv[1]
    end
end

# ─── Path Deduplication ─────────────────────────────────────────────────────────
# Deduplicate PATH (preserve order) to prevent PATH bloat across reloads
set -l seen
set -l newpath

for dir in $PATH
  if not contains -- $dir $seen
    set seen $seen $dir
    set newpath $newpath $dir
  end
end

set -gx PATH $newpath

