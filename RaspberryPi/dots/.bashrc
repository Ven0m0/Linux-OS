#!/bin/bash

# safety
alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'
alias rm='rm -I --preserve-root'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'

# ls
alias la='ls -A'
alias ll='ls -lh'
alias lt='ls -hsS1'
alias ls='ls -ha --group-directories-first --color=auto'
alias cls='clear'
alias ..='cd ..'
alias grep='grep --color=auto'
alias py='python3'

# apt
alias apt='sudo apt'
if has apt-fast; then
  alias apt-fast="sudo apt-fast "
fi
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

# alias to cleanup unused docker containers, images, networks, and volumes
alias docker-clean=' \
  docker container prune -f ; \
  docker image prune -f ; \
  docker network prune -f ; \
  docker volume prune -f '

# poweroff & reboot
alias reboot='sudo reboot'
alias rbt='reboot'
alias poweroff='sudo poweroff'
