# Run welcome message
#function fish_greeting
  #crabfetch -d arch || fastfetch
#end

# ─── Paths─────────────────────────────────────────────────────────
set -x XDG_CONFIG_HOME $HOME/.config
set -x XDG_CACHE_HOME $HOME/.cache
set -x XDG_DATA_HOME $HOME/.local/share
set -x XDG_STATE_HOME $HOME/.local/state

# ─── Environment Tweaks ─────────────────────────────────────────────────────────
set -gx EDITOR micro
set -gx VISUAL $EDITOR
set -gx VIEWER $EDITOR
set -gx GIT_EDITOR $EDITOR
set -gx SYSTEMD_EDITOR $EDITOR
set -x PAGER bat
# set -gx LESS '-RQsn --no-histdups --mouse --wheel-lines=4'
set -gx LESSHISTFILE '-'
set -gx BATPIPE color

# Faster locale
if not status --is-interactive
  set -x LANG C; set -x LC_ALL C
else
  set -x LC_ALL C; set -x LANG C.UTF-8
end

# ─── Only for Interactive Shells ────────────────────────────────────────────────
if status --is-interactive
    # Fast prompt
    set -gx fish_prompt_pwd_dir_length 1
    set -gx __fish_git_prompt_show_informative_status 0
    set -gx __fish_git_prompt_showupstream none

    # Aliases: safe & efficient defaults
    alias cat='bat --strip-ansi=auto -p --paging=auto'

    # My stuff
    alias sshdb='dbclient'
    alias ptch='patch -p1 <'
    alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'
    alias clearnsh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'

    # Enable aliases to be sudo’ed
    alias sudo='sudo '
    alias su='su '
    alias doas='doas '
    alias sudo-rs='sudo-rs '
    alias su='su-rs '

    # Better sudo (if available)
    #if type -q sudo-rs
        #alias sudo sudo-rs
    #end
    #if type -q su-rs
        #alias su su-rs
    #end

    # Creates parent directories on demand.
    alias mkdir='mkdir -p'
    alias edit='$EDITOR'

    # Stops ping after sending 4 ECHO_REQUEST packets.
    alias ping='ping -c 4'
    
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

    # you see nothing...
    set -gx SHELL_MOMMYS_ONLY_NEGATIVE true
    set -gx MOMMY_SWEETIE girl
    alias margo='cargo mommy '
    alias gargo='cargo gg '

    # Reset
    alias clear='command clear; and fish_greeting'
    alias cls='command clear; and fish_greeting'
    abbr --add c clear

   # bind Esc Esc to toggle_sudo
   #source ~/.config/fish/functions/presudo.fish
   #bind \e\e toggle_sudo
   function which
    command -v $argv[1] 
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
