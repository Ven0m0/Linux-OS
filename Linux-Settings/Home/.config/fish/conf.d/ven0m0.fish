## Run crabfetch/fastfetch as welcome message
function fish_greeting
        crabfetch -d arch || fastfetch
end

# ─── Locale (Fast) ─────────────────────────────────────────
set -gx LANG C
set -gx LC_ALL C

# ─── Environment Tweaks ─────────────────────────────────────────────────────────
set -gx EDITOR micro
set -gx VISUAL $EDITOR
alias editor='micro'
# set -gx PAGER less
# set -gx PAGER bat
set -gx LESS '-FRXns --mouse --use-color --no-init'
set -gx LESSHISTFILE '-'

# Avoid expensive VCS prompt delays
set -g __fish_git_prompt_show_informative_status 0
set -g __fish_git_prompt_showupstream none

# ─── Only for Interactive Shells ────────────────────────────────────────────────
if status --is-interactive
    # Locale (Fast& Unicode-Compatible)
    set -gx LANG C.UTF-8
    set -gx LC_ALL C.UTF-8

    # Fast prompt (truncate deep paths)
    set fish_prompt_pwd_dir_length 1

    # https://github.com/iffse/pay-respects
    pay-respects fish --alias | source
    fzf --fish | source

    # Aliases: safe & efficient defaults
    alias cat='bat --strip-ansi=auto --squeeze-blank --style=auto --paging=auto'

    # My stuff
    alias sshdb='dbclient'
    alias ptch='patch -p1 <'
    alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'
    alias clearnsh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'

    # Better sudo (if available)
    if type -q sudo-rs
        alias sudo='sudo-rs'
    end
    if type -q su-rs
        alias su='su-rs'
    end

    if type -q rg
      alias rg='rg --no-stats --color=auto'
      alias grep='rg -uuu --no-stats --color=auto'
      alias fgrep='rg -uuu --no-stats --color=auto -E UTF-8'
      alias egrep='rg --no-stats --color=auto'
    else
      alias grep='grep --color=auto'
      alias fgrep='fgrep --color=auto'
      alias egrep='egrep --color=auto'
    end

    # Quick clear
    abbr --add c 'clear'
    abbr --add cls 'clear'

    bind \e\e toggle_sudo
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

