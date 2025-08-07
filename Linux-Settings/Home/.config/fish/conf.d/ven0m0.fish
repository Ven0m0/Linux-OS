# ─── Environment Tweaks ─────────────────────────────────────────────────────────
set -gx EDITOR micro
set -gx VISUAL $EDITOR
set -gx VIEWER $EDITOR
set -gx GIT_EDITOR $EDITOR
set -gx SYSTEMD_EDITOR $EDITOR
set -gx PAGER bat
# set -gx LESS '-RQsn --no-histdups --mouse --wheel-lines=4'
set -gx LESSHISTFILE '-'
set -gx BATPIPE color

# Fuzzy
set -gx FZF_DEFAULT_OPTS '--inline-info' '--tiebreak=index' '--layout=reverse-list' '--height=70%' '--preview=bat --color=always -s {}' '--preview-window=right:50%'
set -gx FZF_DEFAULT_COMMAND 'fd -tf -F --strip-cwd-prefix --exclude .git'
set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
set -gx SKIM_DEFAULT_COMMAND 'fd -tf -F --strip-cwd-prefix --exclude .git; or rg --files; or find .'
set -gx SKIM_DEFAULT_OPTIONS '--inline-info' '--tiebreak=index' '--layout=reverse-list' '--height=70%' '--preview=bat --color=always -s {}' '--preview-window=right:50%'

# Faster locale
#if status --is-interactive
  #set -x LC_ALL C; set -x LANG C.UTF-8
#else
  #set -x LANG C; set -x LC_ALL C
#end

# ─── Only for Interactive Shells ────────────────────────────────────────────────
if status --is-interactive
    # Fast prompt
    set -gx fish_prompt_pwd_dir_length 1
    set -gx __fish_git_prompt_show_informative_status 0
    set -gx __fish_git_prompt_showupstream none

    # Aliases: safe & efficient defaults
    alias cat='bat -pp --strip-ansi=auto '

    # My stuff
    alias sshdb='dbclient'
    alias ptch='patch -p1 <'
    alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'
    alias clearnsh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'

    # Enable aliases to be sudo’ed
    alias sudo='sudo '
    alias doas='doas '
    alias sudo-rs='sudo-rs '

    # Creates parent directories on demand.
    alias mkdir='mkdir -p '
    alias ed='$EDITOR '

    # Stops ping after sending 4 ECHO_REQUEST packets.
    alias ping='ping -c 4'

    if type -q rg
      functions -e rg 2>/dev/null # reset due to cachyos-fish-config
      alias rg='rg --color=auto -S --engine=auto --block-buffered'
    end
    
    if type -q ugrep
      functions -e grep 2>/dev/null
      alias grep="ugrep --color=auto"
      functions -e fgrep 2>/dev/null
      alias egrep="ugrep -E --color=auto"
      functions -e egrep 2>/dev/null
      alias fgrep="ugrep -F --color=auto"
    else
      alias grep="grep --color=auto"
      alias fgrep="fgrep --color=auto"
      alias egrep="egrep --color=auto"
    end

    # Reset
    alias clear='command clear; and fish_greeting'
    alias cls='command clear; and fish_greeting'
    abbr --add c clear
    
    # bind Esc Esc to toggle_sudo
    #source ~/.config/fish/functions/presudo.fish
    #bind \e\e toggle_sudo
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
