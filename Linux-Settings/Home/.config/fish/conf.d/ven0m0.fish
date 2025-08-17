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
set -gx FZF_DEFAULT_OPTS '--inline-info --tiebreak=index --layout=reverse-list --height=70% --select-1 --exit-0'
set -gx FZF_DEFAULT_COMMAND 'fd -tf -F --strip-cwd-prefix --exclude .git'
set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
set -gx SKIM_DEFAULT_COMMAND 'fd -tf -F --strip-cwd-prefix --exclude .git; or rg --files; or find .'
set -gx SKIM_DEFAULT_OPTIONS $FZF_DEFAULT_OPTS

# ─── Only for Interactive Shells ────────────────────────────────────────────────
if status --is-interactive >/dev/null 2>&1
    # Aliases: safe & efficient defaults
    alias cat='bat -pp --strip-ansi=auto '

    # My stuff
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

    if type -q rg >/dev/null 2>&1
      functions -e rg 2>/dev/null # reset due to cachyos-fish-config
      alias rg='rg --color=auto -S --engine=auto --block-buffered'
    end

    if type -q rg
        functions -e grep; and alias grep="LC_ALL=C rg -S --color=auto"
        functions -e fgrep; and alias egrep="rg -SF --color=auto"
        functions -e egrep; and alias fgrep="rg -Se --color=auto"
        functions -e rg; and alias rg="LC_ALL=C rg -NFS --no-unicode --engine=default --mmap --threads $(nproc 2>/dev/null)"
    else if type -q ugrep
        functions -e grep; and alias grep="LC_ALL=C ugrep --color=auto"
        functions -e fgrep; and alias egrep="ugrep -F --color=auto"
        functions -e egrep; and alias fgrep="ugrep -E --color=auto"
        functions -e ug; and alias ug='LC_ALL=C ug -sjFU -J $(nproc 2>/dev/null) --color=auto'
    else
        functions -e grep; and alias grep="LC_ALL=C grep --color=auto"
        functions -e fgrep; and alias fgrep="fgrep --color=auto"
        functions -e egrep; and alias egrep="egrep --color=auto"
    end

    # Reset
    alias clear='command clear; and fish_greeting 2>/dev/null'
    alias cls='command clear; and fish_greeting 2>/dev/null'
    abbr -a c clear
    abbr -a ed 'edit'

    abbr -a py 'python3'
    
    # bind Esc Esc to toggle_sudo
    #source ~/.config/fish/functions/presudo.fish
    #bind \e\e toggle_sudo
    
    function mkdircd
        mkdir -p $argv; and cd $argv[-1]
    end
    function ip
        command ip --color=auto $argv
    end

end
# ─── Path Deduplication ─────────────────────────────────────────────────────────
# Deduplicate PATH (preserve order) to prevent PATH bloat across reloads
set -l seen
set -l newpath
for dir in $PATH
  if not contains -- $dir $seen 2>/dev/null
    set seen $seen $dir
    set newpath $newpath $dir
  end
end
set -gx PATH $newpath
