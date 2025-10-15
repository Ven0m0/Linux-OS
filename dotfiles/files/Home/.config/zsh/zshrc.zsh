#!/usr/bin/env zsh
# zshrc.zsh - Interactive shell configuration
# This file is sourced for interactive shells

# ──────────── Performance Profiling (optional) ────────────
# Uncomment to profile zsh startup time
# zmodload zsh/zprof

# ──────────── ZSH Options ────────────

# History
setopt APPEND_HISTORY           # Append to history file
setopt EXTENDED_HISTORY         # Save timestamp and duration
setopt HIST_EXPIRE_DUPS_FIRST   # Expire duplicates first
setopt HIST_FIND_NO_DUPS        # Don't show duplicates in search
setopt HIST_IGNORE_ALL_DUPS     # Remove older duplicate entries
setopt HIST_IGNORE_DUPS         # Don't record duplicates
setopt HIST_IGNORE_SPACE        # Don't record commands starting with space
setopt HIST_REDUCE_BLANKS       # Remove superfluous blanks
setopt HIST_SAVE_NO_DUPS        # Don't save duplicates
setopt HIST_VERIFY              # Don't execute immediately upon history expansion
setopt INC_APPEND_HISTORY       # Write to history file immediately
setopt SHARE_HISTORY            # Share history between sessions

# Directory navigation
setopt AUTO_CD                  # cd by typing directory name
setopt AUTO_PUSHD               # Push directories onto stack
setopt PUSHD_IGNORE_DUPS        # Don't push duplicates
setopt PUSHD_MINUS              # Exchange meaning of + and -
setopt PUSHD_SILENT             # Don't print directory stack
setopt PUSHD_TO_HOME            # Push to home if no arguments

# Completion
setopt ALWAYS_TO_END            # Move cursor to end after completion
setopt AUTO_LIST                # List choices on ambiguous completion
setopt AUTO_MENU                # Show completion menu on tab
setopt AUTO_PARAM_SLASH         # Add slash after completing directories
setopt COMPLETE_IN_WORD         # Complete from both ends of word
setopt LIST_PACKED              # Compact completion lists
setopt NO_BEEP                  # Don't beep on errors
setopt NO_LIST_BEEP             # Don't beep on ambiguous completion

# Globbing
setopt EXTENDED_GLOB            # Extended globbing
setopt GLOB_DOTS                # Include dotfiles in globbing
setopt NUMERIC_GLOB_SORT        # Sort filenames numerically
setopt NO_CASE_GLOB             # Case insensitive globbing

# Job control
setopt AUTO_CONTINUE            # Automatically continue stopped jobs
setopt AUTO_RESUME              # Resume jobs on name match
setopt LONG_LIST_JOBS           # List jobs in long format
setopt NOTIFY                   # Report job status immediately

# I/O
setopt CORRECT                  # Command correction
setopt INTERACTIVE_COMMENTS     # Allow comments in interactive shell
setopt NO_CLOBBER               # Don't overwrite files with >
setopt RC_QUOTES                # Allow '' to represent '

# ──────────── Key Bindings ────────────
# Use emacs-style key bindings (can change to 'bindkey -v' for vi mode)
bindkey -e

# History search
bindkey '^[[A' history-substring-search-up    # Up arrow
bindkey '^[[B' history-substring-search-down  # Down arrow
bindkey '^P' history-substring-search-up
bindkey '^N' history-substring-search-down

# Better word navigation
bindkey '^[[1;5C' forward-word      # Ctrl+Right
bindkey '^[[1;5D' backward-word     # Ctrl+Left
bindkey '^[[H' beginning-of-line    # Home
bindkey '^[[F' end-of-line          # End
bindkey '^[[3~' delete-char         # Delete

# Alt+Backspace to delete word
bindkey '^H' backward-kill-word

# Ctrl+U to delete to beginning of line
bindkey '^U' backward-kill-line

# ──────────── Completion System ────────────
autoload -Uz compinit

# Load completion only once a day for performance
if [[ -n "${ZSH_COMPDUMP}"(#qN.mh+24) ]]; then
  compinit -d "${ZSH_COMPDUMP}"
else
  compinit -C -d "${ZSH_COMPDUMP}"
fi

# Completion styles
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${ZSH_CACHE_DIR}/zcompcache"
zstyle ':completion:*:*:*:*:descriptions' format '%F{green}-- %d --%f'
zstyle ':completion:*:*:*:*:corrections' format '%F{yellow}!- %d (errors: %e) -!%f'
zstyle ':completion:*:messages' format ' %F{purple} -- %d --%f'
zstyle ':completion:*:warnings' format ' %F{red}-- no matches found --%f'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:*:-command-:*:*' group-order aliases builtins functions commands

# Process completion
zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

# ──────────── Color Support ────────────
autoload -Uz colors && colors

# ──────────── Prompt Configuration ────────────
# Enable parameter expansion in prompts
setopt PROMPT_SUBST

# Git prompt function
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' stagedstr '%F{green}●%f'
zstyle ':vcs_info:*' unstagedstr '%F{yellow}●%f'
zstyle ':vcs_info:git:*' formats ' %F{blue}(%f%F{red}%b%f%c%u%F{blue})%f'
zstyle ':vcs_info:git:*' actionformats ' %F{blue}(%f%F{red}%b%f|%F{cyan}%a%f%c%u%F{blue})%f'

precmd() {
  vcs_info
}

# Build prompt
PROMPT='%F{cyan}╭─%f'                           # Top corner
PROMPT+='%F{green}%n%f'                         # Username
PROMPT+='%F{white}@%f'                          # @
PROMPT+='%F{blue}%m%f'                          # Hostname
PROMPT+=' %F{yellow}%~%f'                       # Working directory
PROMPT+='${vcs_info_msg_0_}'                    # Git info
PROMPT+=$'\n'                                   # Newline
PROMPT+='%F{cyan}╰─%f'                          # Bottom corner
PROMPT+='%(?.%F{green}.%F{red})❯%f '           # Prompt symbol (green if success, red if error)

# Right prompt with time
RPROMPT='%F{242}%*%f'                           # Time

# ──────────── Aliases ────────────

# Preferred tools (Rust alternatives)
if command -v eza &>/dev/null; then
  alias ls='eza --group-directories-first --icons'
  alias ll='eza -l --group-directories-first --icons --git'
  alias la='eza -la --group-directories-first --icons --git'
  alias lt='eza --tree --level=2 --icons'
else
  alias ls='ls --color=auto --group-directories-first'
  alias ll='ls -lh'
  alias la='ls -lAh'
fi

if command -v bat &>/dev/null; then
  alias cat='bat --style=plain --paging=never'
  alias catt='/usr/bin/cat'
fi

if command -v rg &>/dev/null; then
  alias grep='rg'
  alias grp='/usr/bin/grep --color=auto'
else
  alias grep='grep --color=auto'
fi

if command -v fd &>/dev/null; then
  alias find='fd'
  alias fnd='/usr/bin/find'
fi

if command -v dust &>/dev/null; then
  alias du='dust'
  alias duu='/usr/bin/du'
fi

if command -v btm &>/dev/null; then
  alias top='btm'
  alias htop='btm'
fi

if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
  alias cd='z'
fi

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias ln='ln -i'

# Quick navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# Directory listing
alias l='ls'
alias dir='ls'

# File operations
alias mkdir='mkdir -pv'
alias which='type -a'

# Pacman/Paru/Yay aliases (Arch)
if command -v paru &>/dev/null; then
  alias p='paru'
  alias pi='paru -S'
  alias pr='paru -R'
  alias prs='paru -Rs'
  alias pu='paru -Syu'
  alias ps='paru -Ss'
  alias pq='paru -Q'
  alias pqi='paru -Qi'
  alias pql='paru -Ql'
  alias pc='paru -Sc'
  alias pcc='paru -Scc'
elif command -v yay &>/dev/null; then
  alias p='yay'
  alias pi='yay -S'
  alias pr='yay -R'
  alias prs='yay -Rs'
  alias pu='yay -Syu'
  alias ps='yay -Ss'
  alias pq='yay -Q'
  alias pqi='yay -Qi'
  alias pql='yay -Ql'
  alias pc='yay -Sc'
  alias pcc='yay -Scc'
elif command -v pacman &>/dev/null; then
  alias p='sudo pacman'
  alias pi='sudo pacman -S'
  alias pr='sudo pacman -R'
  alias prs='sudo pacman -Rs'
  alias pu='sudo pacman -Syu'
  alias ps='pacman -Ss'
  alias pq='pacman -Q'
  alias pqi='pacman -Qi'
  alias pql='pacman -Ql'
  alias pc='sudo pacman -Sc'
  alias pcc='sudo pacman -Scc'
fi

# Git aliases
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -v'
alias gcm='git commit -m'
alias gco='git checkout'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git pull'
alias gp='git push'
alias gst='git status'
alias gsta='git stash'
alias glg='git log --oneline --graph --decorate'

# System
alias df='df -h'
alias free='free -h'
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'
alias sysinfo='inxi -Fxxxz'

# Quick edits
alias zshrc='${EDITOR} ${ZDOTDIR}/.zshrc'
alias zshenv='${EDITOR} ${ZDOTDIR}/zshenv.zsh'
alias aliases='${EDITOR} ${ZDOTDIR}/zshrc.zsh'

# Reload zsh config
alias reload='source ${ZDOTDIR}/.zshrc && echo "ZSH config reloaded!"'

# Network
alias myip='curl -s ifconfig.me'
alias ports='netstat -tulanp'

# ──────────── Functions ────────────

# Create and cd into directory
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Extract various archive types
extract() {
  if [[ -f "$1" ]]; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1"     ;;
      *.tar.gz)    tar xzf "$1"     ;;
      *.tar.xz)    tar xJf "$1"     ;;
      *.bz2)       bunzip2 "$1"     ;;
      *.rar)       unrar x "$1"     ;;
      *.gz)        gunzip "$1"      ;;
      *.tar)       tar xf "$1"      ;;
      *.tbz2)      tar xjf "$1"     ;;
      *.tgz)       tar xzf "$1"     ;;
      *.zip)       unzip "$1"       ;;
      *.Z)         uncompress "$1"  ;;
      *.7z)        7z x "$1"        ;;
      *.zst)       unzstd "$1"      ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Fuzzy find and cd
fcd() {
  local dir
  dir=$(find ${1:-.} -path '*/\.*' -prune -o -type d -print 2> /dev/null | fzf +m) && cd "$dir"
}

# Fuzzy find and edit
fvim() {
  local file
  file=$(fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}') && ${EDITOR} "$file"
}

# Git fuzzy checkout
fgco() {
  local branch
  branch=$(git branch --all | grep -v HEAD | sed "s/.* //" | sed "s#remotes/[^/]*/##" | sort -u | fzf +m) && git checkout "$branch"
}

# Quick backup
bak() {
  cp -r "$1" "${1}.bak.$(date +%Y%m%d-%H%M%S)"
}

# List largest directories
dsort() {
  du -shx -- * | sort -rh | head -n "${1:-20}"
}

# Find and kill process
fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
  if [[ -n "$pid" ]]; then
    echo "$pid" | xargs kill -"${1:-9}"
  fi
}

# Update system
sysupdate() {
  if command -v paru &>/dev/null; then
    paru -Syu --noconfirm
  elif command -v yay &>/dev/null; then
    yay -Syu --noconfirm
  elif command -v pacman &>/dev/null; then
    sudo pacman -Syu --noconfirm
  fi
}

# Clean system
sysclean() {
  if command -v paru &>/dev/null; then
    paru -Sc --noconfirm
    paru -Rns $(paru -Qtdq) --noconfirm 2>/dev/null || true
  elif command -v yay &>/dev/null; then
    yay -Sc --noconfirm
    yay -Rns $(yay -Qtdq) --noconfirm 2>/dev/null || true
  elif command -v pacman &>/dev/null; then
    sudo pacman -Sc --noconfirm
    sudo pacman -Rns $(pacman -Qtdq) --noconfirm 2>/dev/null || true
  fi
  
  # Clean cache
  [[ -d "$HOME/.cache" ]] && find "$HOME/.cache" -type f -atime +30 -delete 2>/dev/null
}

# ──────────── Plugin Loading ────────────

# Load history substring search if available
if [[ -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
fi

# Load syntax highlighting if available (should be loaded last)
if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Load autosuggestions if available
if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
fi

# ──────────── Local Configuration ────────────
# Load machine-specific configuration if it exists
if [[ -f "${ZDOTDIR}/.zshrc.local" ]]; then
  source "${ZDOTDIR}/.zshrc.local"
fi

# ──────────── Performance Profiling (optional) ────────────
# Uncomment to see startup time profile
# zprof
