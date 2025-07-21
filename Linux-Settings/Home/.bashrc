# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

. "$HOME/.cargo/env"

PROMPT_DIRTRIM=2
#PS1='[\u@\h \w]\$ ' # Default

# bash-prompt-generator.org
C_USER='\[\e[38;5;201m\]'
C_HOST='\[\e[38;5;33m\]'
C_PATH='\[\e[38;5;129m\]'
C_RESET='\[\e[0m\]'
C_BLINK='\[\e[5m\]'
PS1="[${C_USER}\u${C_RESET}@${C_HOST}\h${C_RESET}|${C_PATH}\w${C_RESET}]${C_BLINK}\$${C_RESET}"

# github.com/iffse/pay-respects
if command -v pay-respects >/dev/null 2>&1; then
    eval "$(pay-respects bash --alias)"
fi

# eval "$(pay-respects bash --alias)"
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
HISTSIZE=1000
HISTFILESIZE=${HISTSIZE}
HISTCONTROL="erasedups:ignoreboth:ignorespace"
HISTIGNORE="&:ls:[bf]g:help:clear:exit:history:bash:fish"
HISTTIMEFORMAT='%F %T '
shopt -s histappend
shopt -s no_empty_cmd_completion
shopt -s checkwinsize
shopt -s globstar
shopt -s nocaseglob
shopt -s cmdhist
shopt -s autocd 2> /dev/null
shopt -s dirspell 2> /dev/null
shopt -s cdspell 2> /dev/null
shopt -s hostcomplete
shopt -u checkhash
set -o noclobber

# Binds
bind 'set completion-query-items 0'
bind 'set page-completions off'
bind 'set show-all-if-ambiguous on'
bind 'set menu-complete-display-prefix on'
bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind "set mark-symlinked-directories on"

# Deduplicate PATH (preserve order) — pure Bash (requires Bash 4+)
dedupe_path() {
  local IFS=':' i dir
  declare -A seen
  local -a parts new_parts=()
  # read into an array
  read -r -a parts <<< "$PATH"
  for dir in "${parts[@]}"; do
    [[ -z $dir ]] && continue     # skip empty
    if [[ -z ${seen[$dir]} ]]; then
      seen[$dir]=1
      new_parts+=("$dir")
    fi
  done
  # reassemble
  PATH="${new_parts[*]}"
  PATH="${PATH// /:}"               # replace spaces with colons
  export PATH
}
dedupe_path
