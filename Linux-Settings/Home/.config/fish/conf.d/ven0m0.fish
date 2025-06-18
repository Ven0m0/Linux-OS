# https://github.com/iffse/pay-respects
pay-respects fish --alias | source

alias sshdb='dbclient'
alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'

alias cat='bat --strip-ansi=auto'
alias du='dust'

alias cleanmem='sync; echo 3 | sudo tee /proc/sys/vm/drop_caches'
alias parallel='parallel -j 0 --load 75% --fast --pipe-part'

# Better sudo
if type -q sudo-rs
    alias sudo='sudo-rs'
else if type -q doas
    alias sudo='doas'
end
