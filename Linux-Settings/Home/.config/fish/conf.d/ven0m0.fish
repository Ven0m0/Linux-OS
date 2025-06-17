# https://github.com/iffse/pay-respects
pay-respects fish --alias | source

# alias ssh='dbclient'
alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'

alias cat='bat --strip-ansi=auto'

alias du='dust'

# Better sudo
if type -q sudo-rs
    alias sudo='sudo-rs'
else if type -q doas
    alias sudo='doas'
end

# Ripgrep
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
