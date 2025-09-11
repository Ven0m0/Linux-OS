#!/bin/bash
# ~/.bashrc

[[ $- != *i* ]] && return
#──────────── Helpers ────────────
has(){ LC_ALL=C command -v -- "$1" &>/dev/null; } # Check for command
# hasname(){ local x; x=$(LC_ALL=C type -P -- "$1") || return; printf '%s\n' "${x##*/}"; } # Basename of command
# p(){ printf '%s\n' "$*" 2>/dev/null; } # Print-echo
# pe(){ printf '%b\n' "$*" 2>/dev/null; } # Print-echo for color
_ifsource(){ [[ -f "$1" ]] && . -- "$1" 2>/dev/null || :; } # Source file if it exists
_prependpath(){ [[ -d "$1" ]] && [[ ":$PATH:" != *":$1:"* ]] && PATH="$1${PATH:+:$PATH}"; } # Only prepend if not already in PATH
#──────────── Sourcing ────────────
_ifsource "/etc/bashrc"
_ifsource "/usr/share/bash-completion/bash_completion" || _ifsource "/etc/bash_completion"
#──────────── Conf ────────────
HISTSIZE=10000 
HISTFILESIZE="$HISTSIZE"
HISTCONTROL="erasedups:ignoreboth"
HISTIGNORE="&:ls:[bf]g:help:clear:printf:exit:history:bash:fish:?:??"
HISTTIMEFORMAT='%F %T '
HISTFILE="$HOME/.bash_history"
CDPATH=".:$HOME:/"
ulimit -c 0 &>/dev/null # disable core dumps
shopt -s histappend cmdhist checkwinsize dirspell cdable_vars \
         cdspell autocd hostcomplete no_empty_cmd_completion &>/dev/null
stty -ixon -ixoff -ixany &>/dev/null
set +H
_editor_cmd="$(command -v micro 2>/dev/null || :)"; _editor_cmd="${_editor_cmd##*/}"; EDITOR="${_editor_cmd:-nano}"
export EDITOR VISUAL="$EDITOR" VIEWER="$EDITOR" GIT_EDITOR="$EDITOR" SYSTEMD_EDITOR="$EDITOR" FCEDIT="$EDITOR" SUDO_EDITOR="$EDITOR"
export PYTHONOPTIMIZE=2 PYTHONIOENCODING='UTF-8' PYTHON_JIT=1 PYENV_VIRTUALENV_DISABLE_PROMPT=1
export PRTY_NO_VIPS=1 PRTY_NO_RAW=1
export NO_COLOR=1

#if has dircolors; then
  #eval "$(LC_ALL=C dircolors -b)" &>/dev/null
#else
  #export LS_COLORS='no=00:fi=00:di=00;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.tga=01;35:*.tiff=01;35:*.png=01;35:*.mpeg=01;35:*.avi=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:*.xml=00;31:'
#fi
#──────────── Aliases ────────────
# safety
alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'
alias rm='rm -I --preserve-root'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'
# ls
alias la='ls -ah --color=auto --group-directories-first'
alias ll='ls -lh --color=auto --group-directories-first'
alias lt='ls -hsS1 --color=auto --group-directories-first'
alias ls='ls --color=auto --group-directories-first'
alias cls='clear' c='clear'
alias grep='grep --color=auto'


# apt
alias apt='sudo apt'
if command -v apt-fast &>/dev/null; then
  alias apt-fast="sudo apt-fast " apt="sudo apt-fast"
else
  alias apt="sudo apt-get"
fi
if command -v nala &>/dev/null, then
  alias nal='sudo \nala'
  alias nala='sudo \nala'
fi

aptsearch(){ if ! nala search -n "$@"; then { apt-cache search "$@" || return 1; } fi; }

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

apacheconfig(){
  if [[ -f /etc/httpd/conf/httpd.conf ]]; then
    "${EDITOR:-nano}" /etc/httpd/conf/httpd.conf
  elif [[ -f /etc/apache2/apache2.conf ]]; then
    "${EDITOR:-nano}" /etc/apache2/apache2.conf
  else
    printf "Error: Apache config file could not be found.\nSearching for possible locations:\n"
    sudo updatedb && locate httpd.conf && locate apache2.conf
fi
}

# poweroff & reboot
alias reboot='sudo reboot'
alias poweroff='sudo poweroff'
#──────────── Aliases 2 / Functions ────────────
sel(){
  local p="${1:-.}"
  [[ -e "$p" ]] || { printf 'sel: not found: %s\n' "$p" >&2; return 1; }
  if [[ -d "$p" ]]; then
    if has eza; then
      command eza -al --color=auto --group-directories-first --icons=auto --no-time --no-git --smart-group --no-user --no-permissions -- "$p"
    else
      command ls -a --color=auto --group-directories-first -- "$p"
    fi
  elif [[ -f "$p" ]]; then
    if has bat; then
      local bn
      bn=$(basename -- "$p")
      command bat -sp --color auto --file-name="$bn" -- "$p"
    else
      command cat -s -- "$p"
    fi
  else
    printf 'sel: not a file/dir: %s\n' "$p" >&2; return 1
  fi
}

sudo-command-line(){
  printf 'toggle sudo at the beginning of the current or the previous command by hitting ESC twice\n'
  [[ ${#READLINE_LINE} -eq 0 ]] && READLINE_LINE=$(fc -l -n -1 | xargs)
  if [[ $READLINE_LINE == sudo\ * ]]; then
    READLINE_LINE="${READLINE_LINE#sudo }"
  else
    READLINE_LINE="sudo $READLINE_LINE"
  fi
  READLINE_POINT="${#READLINE_LINE}"
}
bind -x '"\e\e": sudo-command-line'

cl(){
  local dir="${1:=$HOME}"
    if [[ -d "$dir" ]]; then
      cd "$dir" >/dev/null; ls
    else
      echo "bash: cl: $dir: Directory not found"
    fi
}

cdls(){ command cd -- "$1" && command ls -ah --color=auto --group-directories-first; }
mkcd(){ command mkdir -p -- "$1" && command cd -- "$1"; }

touchf(){ command mkdir -p -- "$(dirname -- "$1")" && command touch -- "$1"; }
alias please='sudo !!'
alias cls='clear' c='clear'
alias sudo='sudo ' doas='doas '
alias mkdir='mkdir -p'
# DIRECTORY NAVIGATION
alias ..="cd -- .."
alias ...="cd -- ../.."
alias ....="cd -- ../../.."
alias ~="cd -- $HOME"
alias cd-="cd -- -"
alias pip='python -m pip' py3='python3' py='python'
#──────────── Bindings (readline) ────────────
bind 'set completion-query-items 150'
bind 'set page-completions off'
bind 'set show-all-if-ambiguous on'
bind 'set show-all-if-unmodified on'
bind 'set menu-complete-display-prefix on'
bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind 'set mark-directories on'
bind "set mark-symlinked-directories on"
bind "set bell-style none"
bind 'set skip-completed-text on'
bind 'set colored-stats on'
bind 'set colored-completion-prefix on'
bind 'set expand-tilde on'
bind '"Space": magic-space'
bind '"\C-o": kill-whole-line'
bind '"\C-a": beginning-of-line'
bind '"\C-e": end-of-line'
bind '"\e[1;5D": backward-word'
bind '"\e[1;5C": forward-word'
bind 'set enable-bracketed-paste off'
# prefixes the line with sudo , if Alt+s is pressed
#bind '"\ee": "\C-asudo \C-e"'
# https://wiki.archlinux.org/title/Bash
run-help(){ help "$READLINE_LINE" 2>/dev/null || man "$READLINE_LINE"; }
bind -m vi-insert -x '"\eh": run-help'
bind -m emacs -x     '"\eh": run-help'
#──────────── End ────────────
dedupe_path(){
  local IFS=: dir s; declare -A seen
  for dir in $PATH; do
    [[ -n $dir && -z ${seen[$dir]} ]] && seen[$dir]=1 && s="${s:+$s:}$dir"
  done
  [[ -n $s ]] && export PATH="$s"
  command -v systemctl &>/dev/null && command systemctl --user import-environment PATH &>/dev/null
}
dedupe_path
#──────────── Prompt ────────────
# PS1='[\u@\h|\w] \$'
PROMPT_DIRTRIM=2
PROMPT_COMMAND="history -a"
export GIT_PS1_SHOWDIRTYSTATE=false GIT_PS1_OMITSPARSESTATE=true

configure_prompt(){
  command -v starship &>/dev/null && { eval "$(LC_ALL=C starship init bash)"; return; }

  local MGN='\[\e[35m\]' BLU='\[\e[34m\]' YLW='\[\e[33m\]' BLD='\[\e[1m\]' UND='\[\e[4m\]' \
        CYN='\[\e[36m\]' DEF='\[\e[0m\]' RED='\[\e[31m\]'  PNK='\[\e[38;5;205m\]' USERN HOSTL
  USERN="${MGN}\u${DEF}"; [[ $EUID -eq 0 ]] && USERN="${RED}\u${DEF}"
  HOSTL="${BLU}\h${DEF}"; [[ -n $SSH_CONNECTION ]] && HOSTL="${YLW}\h${DEF}"

  PS1="[${USERN}@${HOSTL}${UND}|${DEF}${CYN}\w${DEF}]>${PNK}\A${DEF}|\$? ${BLD}\$${DEF} "
  PS2='> '

  if command -v __git_ps1 &>/dev/null && [[ ${PROMPT_COMMAND:-} != *git_ps1* ]]; then
    export GIT_PS1_OMITSPARSESTATE=1 GIT_PS1_HIDE_IF_PWD_IGNORED=1
    unset GIT_PS1_SHOWDIRTYSTATE GIT_PS1_SHOWSTASHSTATE GIT_PS1_SHOWUPSTREAM GIT_PS1_SHOWUNTRACKEDFILES
    PROMPT_COMMAND="LC_ALL=C __git_ps1 2>/dev/null; ${PROMPT_COMMAND:-}"
  fi
}
configure_prompt
#──────────── Fetch ────────────
if [[ $SHLVL -le 2 ]]; then
  if [ "${stealth:-0}" -eq 1 ]; then
    command -v fastfetch &>/dev/null && LC_ALL=C fastfetch --ds-force-drm --thread --detect-version false 2>/dev/null
  else
    if command -v hyfetch &>/dev/null; then
      LC_ALL=C hyfetch -b fastfetch -m rgb -p transgender 2>/dev/null
    elif command -v fastfetch &>/dev/null; then
      LC_ALL=C fastfetch --ds-force-drm --thread 2>/dev/null
    else
      LC_ALL=C hostnamectl 2>/dev/null
    fi
  fi
fi
