#!/bin/basj

# safety
alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'
alias rm='rm -I --preserve-root'
alias chown='chown'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'

# apt
alias apt='sudo apt'
alias sa='apt'
alias au='sudo apt update && sudo apt upgrade && sudo apt full-upgrade && sudo apt-file update && apt autoremove'
alias ai='sudo apt install'
alias ali='apt list --installed'
alias al='apt list'
alias af='apt-file -x find'
alias ap='apt purge'
alias aar='apt autoremove'
alias i='sudo apt install'

# docker
alias dr='docker run'
alias dps='docker ps'
alias sd='sudo docker'
alias sdr='sudo docker run'
alias dl='docker load'
alias di='docker image'
alias dc='docker container'

# poweroff & reboot
alias reboot='sudo reboot'
alias rbt='reboot'
alias poweroff='sudo poweroff'

# ls
alias la='ls -A'
alias ll='ls -lh'
alias lt='ls -hsS1'
alias ls='ls -ha --group-directories-first --color=auto'
alias cls='clear'
alias ..='cd ..'
alias grep='grep --color=auto'
alias py='python3'

