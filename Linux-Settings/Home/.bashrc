#
# ~/.bashrc
#

export LANG=C LC_ALL=C

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

export LC_ALL=C LANG=C.UTF-8 

PS1='[\u \W]\$ '
. "$HOME/.cargo/env"

# https://github.com/iffse/pay-respects
if command -v pay-respects >/dev/null 2>&1; then
    eval "$(pay-respects bash --alias)"
fi

eval "$(fzf --bash)"
eval "$(starship init bash)"
export EDITOR=micro
export VISUAL=$EDITOR
alias editor='micro'
alias nano='nano -/ ' # Nano modern keybinds
#export GIT_PAGER=delta
#export CARGO_TERM_PAGER=bat
# export PAGER=less
export LESS='-FRXns --mouse --use-color --no-init'
export LESSHISTFILE='-'
# export MANPAGER="less -sRn"
# Faster Skim (fastest to slowest skim command)
export SKIM_DEFAULT_COMMAND='rg --files--glob "!.git/*" || fd --type f --color=never . || find . -type f'

## Useful aliases
# alias sshdb='dbclient'
alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'
# Replace ls with eza
alias ls='eza -al --color=always --group-directories-first --icons' # preferred listing
alias la='eza -a --color=always --group-directories-first --icons'  # all files and dirs
alias ll='eza -l --color=always --group-directories-first --icons'  # long format
alias lt='eza -aT --color=always --group-directories-first --icons' # tree listing
alias l.="eza -a | grep -e '^\.'"                                   # show only dotfiles
# alias cat='bat --strip-ansi=auto --style=auto -s'

# Stops ping after sending 4 ECHO_REQUEST packets.
alias ping='ping -c 4'

# Makes `mount` command output pretty and with a human readable format.
alias mount='mount | column -t'

# Creates parent directories on demand.
alias mkdir='mkdir -p'
alias edit='$EDITOR'

# Enable aliases to be sudo’ed
alias sudo='\sudo '

# Ripgrep
if command -v rg >/dev/null 2>&1; then
    alias rg='rg --no-stats --color=auto'
    alias grep='rg -uuu --no-stats --color=auto'
    alias fgrep='rg -uuu --no-stats --color=auto -E UTF-8'
    alias egrep='rg --no-stats --color=auto'
else
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Quick clear
alias cls='clear'
alias c='clear'

# FD https://github.com/sharkdp/fd
export FZF_DEFAULT_COMMAND='fd -tf -F'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# options
export HISTSIZE=1000
export HISTFILESIZE=${HISTSIZE}
export HISTCONTROL="erasedups:ignoreboth:ignorespace"
# export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"
export HISTIGNORE='&:[ ]*:ls:ll:la:bg:fg:cd:exit:clear:history:fish:bash'
export HISTTIMEFORMAT='%F %T '

export PROMPT_DIRTRIM=2
shopt -s no_empty_cmd_completion
shopt -s globstar
shopt -s nocaseglob
set -o noclobber
shopt -s histappend
shopt -s cmdhist
shopt -s autocd 2> /dev/null
shopt -s dirspell 2> /dev/null
shopt -s cdspell 2> /dev/null
shopt -s checkwinsize

# Binds
bind 'set completion-query-items 0'
bind 'set page-completions off'
bind 'set show-all-if-ambiguous on'
bind 'set menu-complete-display-prefix on'
bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind "set mark-symlinked-directories on"

# Deduplicate PATH (preserve order) — pure Bash (requires Bash 4+)
if [[ ${BASH_VERSINFO[0]} -ge 4 ]]; then
  IFS=: read -ra parts <<< "$PATH"
  declare -A seen
  newpath=()
  for dir in "${parts[@]}"; do
    [[ -n "$dir" && -z "${seen[$dir]}" ]] && newpath+=("$dir") && seen[$dir]=1
  done
  PATH="${newpath[*]}"
  PATH="${PATH// /:}"
  export PATH
else
  # Fallback: use awk one-liner if Bash <4
  export PATH="$(awk -v RS=: '!(seen[$1]++) {paths[++count]=$1} END {for(i=1;i<=count;i++) printf "%s%s", paths[i], (i<count ? ":" : "\n")}' <<<"$PATH")"
fi
