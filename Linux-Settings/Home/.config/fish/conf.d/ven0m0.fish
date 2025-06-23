# Only apply in interactive shells
if status --is-interactive


# https://github.com/iffse/pay-respects
pay-respects fish --alias | source
fzf --fish | source

alias sshdb='dbclient'
alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'

alias cat='bat --strip-ansi=auto'
# alias du='dust -T 16 -b -P'

alias cleanmem='sync; echo 3 | sudo tee /proc/sys/vm/drop_caches'
# alias parallel='parallel -j 0 --load 75% --fast --pipe-part'

# Better sudo
if type -q sudo-rs
    alias sudo 'sudo-rs'
end

if type -q su-rs
    alias su 'su-rs'
end

# Set language/locale for performance
set -gx LC_ALL C
set -gx LANG C

# Use modern pager (if installed)
set -gx PAGER less
set -gx LESS='-FRXn --no-init'


# Truncate long paths in prompt
set fish_prompt_pwd_dir_length 1

# Avoid slowness from some completions
set -g __fish_git_prompt_show_informative_status 0
set -g __fish_git_prompt_showupstream none

# Directory navigation shortcuts
abbr --add .. 'cd ..'
abbr --add ... 'cd ../..'
abbr --add .... 'cd ../../..'
abbr --add --global c 'clear'

end

