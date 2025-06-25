# ─── Locale (Fast & Unicode-Compatible) ─────────────────────────────────────────
set -gx LC_ALL C.UTF-8
set -gx LANG C.UTF-8

# ─── Environment Tweaks ─────────────────────────────────────────────────────────
set -gx EDITOR micro
alias editor='micro'
set -gx PAGER less
set -gx LESS '-FRXns --mouse --use-color --no-init'
set -gx LESSHISTFILE '-'

# ─── Only for Interactive Shells ────────────────────────────────────────────────
if status --is-interactive
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

    # Git abbreviations
    abbr --add g 'git'
    abbr --add ga 'git add'
    abbr --add gc 'git commit'
    abbr --add gp 'git push'
    abbr --add gl 'git pull'

    # Navigation shortcuts
    abbr --add .. 'cd ..'
    abbr --add ... 'cd ../..'
    abbr --add .... 'cd ../../..'

    # Quick clear
    abbr --add c 'clear'

    # Avoid expensive VCS prompt delays
    set -g __fish_git_prompt_show_informative_status 0
    set -g __fish_git_prompt_showupstream none
end

if test -e $HOME/.ssh/config
  if type -q rg
    set hosts (rg --no-filename --no-heading -e '^Host\s+(?!.*[\?\*]).*' $HOME/.ssh/config | awk '{for(i=2;i<=NF;i++) print $i}')
  else
    set hosts (grep '^Host' $HOME/.ssh/config | grep -v '[?*]' | cut -d' ' -f2- | tr ' ' '\n')
  end

  complete -o default -o nospace -W "$hosts" ssh scp sftp
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
