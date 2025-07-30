# ~/.bashrc

# ─── Only for interactive shells ───────────────────────────────────────────
[[ $- != *i* ]] && return
# ─── Prompt ─────────────────────────────────────────────────────────
# bash-prompt-generator.org
# PS1='[\u@\h|\w] \$' # Default
PROMPT_DIRTRIM=2
configure_prompt() {
  if command -v starship &>/dev/null; then
    eval "$(starship init bash 2>/dev/null)" >/dev/null
  else
    local C_USER='\[\e[38;5;201m\]' C_HOST='\[\e[38;5;33m\]' \
          C_PATH='\[\e[38;5;129m\]' C_RESET='\[\e[0m\]' CODE
    CODE='$( (($?)) && printf "\[\e[38;5;203m\]%d\[\e[0m\]" "$?" )'
    PS1="[${C_USER}\u${C_RESET}@${C_HOST}\h${C_RESET}|${C_PATH}\w${C_RESET}]$CODE \$ "
  fi
  command -v mommy &>/dev/null && PROMPT_COMMAND="mommy -1 -s \$?; $PROMPT_COMMAND"
}
configure_prompt
# Remove "$CODE" to remove error codes

# ─── Core Environment + Options ─────────────────────────────────────────────────────
export LANG="${LANG:-C.UTF-8}"; unset LC_ALL
export HOME
export CDPATH=".:~"
ulimit -c 0 2>/dev/null # disable core dumps
shopt -s nullglob globstar 2>/dev/null
shopt -s histappend cmdhist 2>/dev/null
shopt -s checkwinsize 2>/dev/null
shopt -s dirspell cdspell autocd 2>/dev/null
shopt -s hostcomplete no_empty_cmd_completion 2>/dev/null
HISTSIZE=1000
HISTFILESIZE=${HISTSIZE}
HISTCONTROL="erasedups:ignoreboth"
HISTIGNORE="&:ls:[bf]g:help:clear:exit:history:bash:fish:?:??"
HISTTIMEFORMAT='%F %T '
shopt -u mailwarn; unset MAILCHECK # Bash-it

# Pi3 fix low power message warning
[[ $TERM != xterm-256color && $TERM != xterm-ghostty ]] && { setterm --msg off; setterm --bfreq 0; }
setterm --linewrap on

# ─── Sourcing ──────────────────────────────────────────────
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
command -v pay-respects &>/dev/null && eval "$(pay-respects bash --alias 2>/dev/null)" 
command -v batpipe &>/dev/null && eval "$(batpipe 2>/dev/null)"
command -v batman &>/dev/null && eval "$(batman --export-env 2>/dev/null)"
command -v fzf &>/dev/null && eval "$(fzf --bash 2>/dev/null)"
ommand -v sk &>/dev/null && source <(sk --shell bash 2>/dev/null)
# Ghostty
if [[ $TERM == xterm-ghostty && -e "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash" ]]; then
    builtin source "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash"
fi

# ─── Environment ─────────────────────────────────────────────────────────
command -v micro &>/dev/null && EDITOR=micro || EDITOR=nano

for v in VISUAL VIEWER GIT_EDITOR SYSTEMD_EDITOR FCEDIT SUDO_EDITOR; do
  export "$v=$EDITOR"
done

for var in VISUAL VIEWER GIT_EDITOR SYSTEMD_EDITOR FCEDIT SUDO_EDITOR; do
  : "${!var:=$EDITOR}"
  export "$var"
done

git config --global core.editor "$EDITOR" 2>/dev/null

alias nano='nano -/ ' # Nano modern keybinds
command -v curl &>/dev/null && export CURL_HOME="$HOME"
command -v delta &>/dev/null && export GIT_PAGER=delta
if command -v bat &>/dev/null; then
  export PAGER=bat BATPIPE=color
  : "${GIT_PAGER:=bat}"
elif command -v less &>/dev/null; then
  export PAGER=less LESSHISTFILE=-
  export LESS='-FRXns --mouse --use-color --no-init'
  : "${GIT_PAGER:=less}"
fi

# fd‑ignore file
if [[ -f $HOME/.ignore ]]; then
  export FD_IGNORE_FILE="$HOME/.ignore"
elif [[ -f $HOME/.gitignore ]]; then
  export FD_IGNORE_FILE="$HOME/.gitignore"
fi

# ─── Fuzzy finders ─────────────────────────────────────────────────────────
if command -v fd &>/dev/null; then
  FIND_CMD='fd -tf -F --hidden --exclude .git --exclude node_modules --exclude target'
elif command -v rg &>/dev/null; then
  FIND_CMD='rg --files --hidden --glob "!.git" --glob "!node_modules" --glob "!target"'
else
  FIND_CMD='find . -type f ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*"'
fi
export FZF_DEFAULT_COMMAND="$FIND_CMD" SKIM_DEFAULT_COMMAND="$FIND_CMD"
export FZF_DEFAULT_OPTS="--inline-info --tiebreak=index --layout=reverse-list --height=70%"
export FZF_CTRL_T_COMMAND="$FIND_CMD"
export FZF_CTRL_R_OPTS="--color header:italic --header 'Press CTRL-Y to copy command into clipboard'"
export FZF_COMPLETION_OPTS='--border --info=inline'
export FZF_COMPLETION_PATH_OPTS='--walker file,dir,follow,hidden'
export FZF_COMPLETION_DIR_OPTS='--walker dir,follow'
export SKIM_DEFAULT_OPTIONS="$FZF_DEFAULT_OPTS"

# ─── Binds ─────────────────────────────────────────────────────────
bind 'set completion-query-items 0'
#bind 'set page-completions off'
bind 'set show-all-if-ambiguous on'
bind 'set menu-complete-display-prefix on'
bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind "set mark-symlinked-directories on"
bind "set bell-style none"
bind Space:magic-space

# ─── Aliases ─────────────────────────────────────────────────────────
# Enable aliases to be sudo’ed
alias sudo='\sudo '
#alias su='\su '
#alias doas='\doas '
#alias sudo-rs='\sudo-rs '
#alias su='\su-rs '

alias mkdir='mkdir -p '
alias ed='$EDITOR ' sued='sudo $EDITOR '

alias cls='clear' c='clear'
alias ping='ping -c 4' # Stops ping after 4 requests
alias mount='mount | column -t' # human readable format

alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'

command -v bat &>/dev/null && alias cat='bat -pp --strip-ansi=auto '
if command -v eza &>/dev/null; then
  alias ls='eza -al --color=always --group-directories-first --icons' # preferred listing
  alias la='eza -a --color=always --group-directories-first --icons'  # all files and dirs
  alias ll='eza -l --color=always --group-directories-first --icons'  # long format
  alias lt='eza -aT --color=always --group-directories-first --icons' # tree listing
fi
if command -v rg &>/dev/null; then
    alias rg='rg --no-stats --color=auto'
    alias grep='rg -uuu --no-stats --color=auto'
    alias fgrep='rg -uuu --no-stats --color=auto -E UTF-8'
    alias egrep='rg --no-stats --color=auto'
else
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# ─── Utility Functions ─────────────────────────────────────────────
which() { command -v "$1" 2>/dev/null || return 1; }

# Deduplicate PATH (preserve order)
dedupe_path() {
  local dir; local -A seen; local new=()
  for dir in ${PATH//:/ }; do
    [[ -n $dir && -z ${seen[$dir]} ]] && seen[$dir]=1 && new+=("$dir")
  done
  PATH=$(IFS=:; echo "${new[*]}")
}
dedupe_path; export PATH
