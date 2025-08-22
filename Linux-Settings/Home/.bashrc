# ~/.bashrc

[[ $- != *i* ]] && return
#──────────── Helpers ────────────
has(){ LC_ALL=C command -v -- "$1" &>/dev/null; } # Check for command
hasname(){ local x; x=$(LC_ALL=C type -P -- "$1") || return; printf '%s\n' "${x##*/}"; } # Basename of command
p(){ printf '%s\n' "$*" 2>/dev/null; } # Print-echo
pe(){ printf '%b\n' "$*" 2>/dev/null; } # Print-echo for color
_ifsource(){ [[ -f "$1" ]] && . -- "$1" 2>/dev/null || :; } # Source file if it exists
_prependpath(){ [[ -d "$1" ]] && [[ ":$PATH:" != *":$1:"* ]] && PATH="$1${PATH:+:$PATH}"; } # Only prepend if not already in PATH
#──────────── Sourcing ────────────
_ifsource "/etc/bashrc"
_for_each_source=(
  "$HOME/.bash_aliases"
  "$HOME/.bash_functions"
  "$HOME/.fns"
  "$HOME/.funcs"
)
for _src in "${_for_each_source[@]}"; do
  _ifsource "$_src"
done
# completions (quiet)
_ifsource "/usr/share/bash-completion/bash_completion" || _ifsource "/etc/bash_completion"
#──────────── Stealth ────────────
stealth=${stealth:-0} # stealth=1
#──────────── History / Prompt basics ────────────
# PS1='[\u@\h|\w] \$' # bash-prompt-generator.org
HISTSIZE=10000 
HISTFILESIZE="$HISTSIZE"
HISTCONTROL="erasedups:ignoreboth"
HISTIGNORE="&:ls:[bf]g:help:clear:printf:exit:history:bash:fish:?:??"
HISTTIMEFORMAT='%F %T '
HISTFILE="$HOME/.bash_history"
PROMPT_DIRTRIM=2
PROMPT_COMMAND="history -a"
#──────────── Core ────────────
CDPATH=".:$HOME:/"
ulimit -c 0 &>/dev/null # disable core dumps
shopt -s histappend cmdhist checkwinsize dirspell cdable_vars \
         cdspell autocd hostcomplete no_empty_cmd_completion &>/dev/null
# Disable Ctrl-s, Ctrl-q
stty -ixon -ixoff -ixany &>/dev/null
set +H  # disable history expansion that breaks some scripts
# set -o vi # vi mode
#──────────── Env ────────────
_prependpath "$HOME/.local/bin"
_prependpath "$HOME/bin"

# Editor selection: prefer micro, fallback to nano
_editor_cmd="$(command -v micro 2>/dev/null || :)"; _editor_cmd="${_editor_cmd##*/}"; EDITOR="${_editor_cmd:-nano}"
export EDITOR VISUAL="$EDITOR" VIEWER="$EDITOR" GIT_EDITOR="$EDITOR" SYSTEMD_EDITOR="$EDITOR" FCEDIT="$EDITOR" SUDO_EDITOR="$EDITOR"

# https://wiki.archlinux.org/title/Locale
unset LC_ALL _editor_cmd
export LANG="${LANG:-C.UTF-8}" \
       LANGUAGE="en_US:en:C" \
       LC_MEASUREMENT=C \
       LC_COLLATE=C \
       LC_CTYPE=C

# Mimalloc & Jemalloc
# https://github.com/microsoft/mimalloc/blob/main/docs/environment.html
export MALLOC_CONF="metadata_thp:auto,tcache:true,background_thread:true,percpu_arena:percpu,trust_madvise:enabled"
export _RJEM_MALLOC_CONF="$MALLOC_CONF" MIMALLOC_VERBOSE=0 MIMALLOC_SHOW_ERRORS=0 MIMALLOC_SHOW_STATS=0 MIMALLOC_ALLOW_LARGE_OS_PAGES=1 MIMALLOC_PURGE_DELAY=25 MIMALLOC_ARENA_EAGER_COMMIT=2

# Delta / bat integration
if has delta; then
  export GIT_PAGER=delta
  if has batdiff || has batdiff.sh; then
    export BATDIFF_USE_DELTA=true
  fi
fi
if has bat; then
  export PAGER=bat BAT_STYLE=auto BAT_THEME=ansi BATPIPE=color GIT_PAGER="${GIT_PAGER:-bat}"
  alias cat='bat -spp --'
  alias bat='bat --color auto --'
  has batman && eval "$(LC_ALL=C batman --export-env 2>/dev/null)" 2>/dev/null || true
  has batgrep && alias batgrep='batgrep --rga -S --color 2>/dev/null' || true
elif has less; then
  export PAGER=less LESSHISTFILE="-" LESS='-FRXns --mouse --use-color --no-init' GIT_PAGER="${GIT_PAGER:-less}"
fi
if has less; then
  export LESS_TERMCAP_md=$'\e[01;31m' LESS_TERMCAP_me=$'\e[0m' LESS_TERMCAP_us=$'\e[01;32m' LESS_TERMCAP_ue=$'\e[0m' LESS_TERMCAP_so=$'\e[45;93m' LESS_TERMCAP_se=$'\e[0m'
  has lesspipe && eval "$(SHELL=/bin/sh LC_ALL=C lesspipe 2>/dev/null)" 2>/dev/null || true
fi

# XDG + misc
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:=$HOME/.config}" \
       XDG_DATA_HOME="${XDG_DATA_HOME:=$HOME/.local/share}" \
       XDG_STATE_HOME="${XDG_STATE_HOME:=$HOME/.local/state}" \
       XDG_CACHE_HOME="${XDG_CACHE_HOME:=$HOME/.cache}"
# https://www.reddit.com/r/programming/comments/109rjuj/how_setting_the_tz_environment_variable_avoids
export INPUTRC="$HOME/.inputrc"
export CURL_HOME="$HOME"
export GPG_TTY="$(tty)" TZ="Europe/Berlin" CLICOLOR=1
  
# Cargo / rustenv
if has cargo; then
  _ifsource "$HOME/.cargo/env"
  export CARGO_HOME="${HOME}/.cargo" RUSTUP_HOME="${HOME}/.rustup"
  _prependpath "${CARGO_HOME}/bin"
fi
export PYTHONOPTIMIZE=2 PYTHONIOENCODING='UTF-8' PYTHON_JIT=1 PYENV_VIRTUALENV_DISABLE_PROMPT=1
export FD_IGNORE_FILE="${HOME}/.ignore" FIGNORE="argo.lock"
export ZSTD_NBTHREADS=0 ELECTRON_OZONE_PLATFORM_HINT=auto _JAVA_AWT_WM_NONREPARENTING=1 GTK_USE_PORTAL=1

# Wayland
if has qt6ct; then
  export QT_QPA_PLATFORMTHEME='qt6ct'
elif has qt5ct; then
  export QT_QPA_PLATFORMTHEME='qt5ct'
fi
if [[ ${XDG_SESSION_TYPE:-} == "wayland" ]]; then
  export GDK_BACKEND=wayland QT_QPA_PLATFORM=wayland SDL_VIDEODRIVER=wayland CLUTTER_BACKEND=wayland \
    MOZ_ENABLE_WAYLAND=1 MOZ_ENABLE_XINPUT2=1 QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QT_AUTO_SCREEN_SCALE_FACTOR=1
fi

export LS_COLORS='no=00:fi=00:di=00;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.tga=01;35:*.tiff=01;35:*.png=01;35:*.mpeg=01;35:*.avi=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:*.xml=00;31:'
#──────────── Fuzzy finders ────────────
fuzzy_finders(){
  local FIND_CMD
  if has fd; then
    FIND_CMD='fd -tf -F --hidden --exclude .git --exclude node_modules --exclude target'
  elif has rg; then
    FIND_CMD='rg --files --hidden --glob "!.git" --glob "!node_modules" --glob "!target"'
  else
    FIND_CMD='find . -type f ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*"'
  fi
  declare -x FZF_DEFAULT_COMMAND="$FIND_CMD"
  declare -x FZF_CTRL_T_COMMAND="$FIND_CMD"
  declare -x FZF_DEFAULT_OPTS='--info=inline --layout=reverse --tiebreak=index --height=70%'
  declare -x FZF_CTRL_T_OPTS="--select-1 --exit-0 --preview 'bat -n --color=auto --line-range=:250 -- {} 2>/dev/null || cat -- {} 2>/dev/null'"
  declare -x FZF_CTRL_R_OPTS="--select-1 --exit-0 --no-sort --exact --preview 'echo {}' --preview-window down:3:hidden:wrap --bind '?:toggle-preview'"
  declare -x FZF_ALT_C_OPTS="--select-1 --exit-0 --walker-skip .git,node_modules,target --preview 'tree -C {} 2>/dev/null | head -200'"
  declare -x FZF_COMPLETION_OPTS='--border --info=inline --tiebreak=index'
  declare -x FZF_COMPLETION_PATH_OPTS="--info=inline --tiebreak=index --walker file,dir,follow,hidden"
  declare -x FZF_COMPLETION_DIR_OPTS="--info=inline --tiebreak=index --walker dir,follow"
  mkdir -p -- "$HOME/.config/bash/completions" 2>/dev/null
  if has fzf; then
    [[ -f /usr/share/fzf/key-bindings.bash ]] && . "/usr/share/fzf/key-bindings.bash" 2>/dev/null || :
    if [[ ! -f $HOME/.config/bash/completions/fzf_completion.bash ]]; then
      fzf --bash 2>/dev/null >| "$HOME/.config/bash/completions/fzf_completion.bash"
    fi
    . "$HOME/.config/bash/completions/fzf_completion.bash" 2>/dev/null || :
  fi
  if has sk; then
    declare -x SKIM_DEFAULT_COMMAND="$FIND_CMD"
    declare -x SKIM_DEFAULT_OPTIONS="${FZF_DEFAULT_OPTS:-}"
    alias fzf='sk ' 2>/dev/null || true
    [[ -f /usr/share/skim/key-bindings.bash ]] && . "/usr/share/skim/key-bindings.bash" 2>/dev/null || :
    if [[ ! -f $HOME/.config/bash/completions/sk_completion.bash ]]; then
      sk --shell bash 2>/dev/null >| "$HOME/.config/bash/completions/sk_completion.bash"
    fi
    . "$HOME/.config/bash/completions/sk_completion.bash" 2>/dev/null || :
  fi
}
fuzzy_finders
#──────────── Completions ────────────
complete -cf sudo 2>/dev/null
command -v pay-respects &>/dev/null && eval "$(LC_ALL=C pay-respects bash 2>/dev/null)" 2>/dev/null || :
# Ghostty
[[ $TERM == xterm-ghostty && -e "${GHOSTTY_RESOURCES_DIR:-}/shell-integration/bash/ghostty.bash" ]] && . "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash" 2>/dev/null || :
# Wikiman
# [[ command -v wikiman &>/dev/null && -f /usr/share/wikiman/widgets/widget.bash ]] && . "/usr/share/wikiman/widgets/widget.bash" 2>/dev/null
#──────────── Functions ────────────
# Having to set a new script as executable always annoys me.
runch(){
  shopt -u nullglob nocaseglob; local s="$1"
  if [[ -z $s ]]; then
    printf 'runch: missing script argument\nUsage: runch <script>\n' >&2; return 2
  fi
  if [[ ! -f $s ]]; then
    printf 'runch: file not found: %s\n' "$s" >&2; return 1
  fi
  if ! command chmod u+x -- "$s" 2>/dev/null; then
    printf 'runch: cannot make executable: %s\n' "$s" >&2; return 1    
  fi
  if [[ $s == */* ]]; then
    "$s"
  else
    "./$s"
  fi
}

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

gcom(){ LC_ALL=C command git add -- . && LC_ALL=C command git commit -m "$1"; }
lazyg(){ LC_ALL=C command git add -- . && LC_ALL=C command git commit -m -- "$1" && LC_ALL=C command git push; }
symbreak(){ LC_ALL=C command find -L "${1:-.}" -type l; }

command -v hyperfine &>/dev/null && hypertest(){ LC_ALL=C command hyperfine -w 25 -m 50 -i -- "$@"; }

touchf(){ command mkdir -p -- "$(dirname -- "$1")" && command touch -- "$1"; }
#──────────── Aliases ────────────
# Enable aliases to be sudo’ed
alias sudo='sudo ' sudo-rs='sudo-rs ' doas='doas '
alias mkdir='mkdir -p'
alias ed='$EDITOR' mi='$EDITOR' smi='sudo $EDITOR'
alias please='sudo !!'
alias pacman1='sudo pacman --noconfirm --needed --color=auto'
alias paru1='paru --skipreview --noconfirm --needed'
alias cls='clear' c='clear'
alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'

if has eza; then
  alias ls='eza -F --color=auto --group-directories-first --icons=auto'
  alias la='eza -AF --color=auto --group-directories-first --icons=auto'
  alias ll='eza -AlF --color=auto --group-directories-first --icons=auto --no-time --no-git --smart-group --no-user --no-permissions'
  alias lt='eza -ATF -L 3 --color=auto --group-directories-first --icons=auto --no-time --no-git --smart-group --no-user --no-permissions'
else
  alias ls='ls --color=auto --group-directories-first -C'
  alias la='ls --color=auto --group-directories-first -A'
  alias ll='ls --color=auto --group-directories-first -oh'
  alias lt='ls --color=auto --group-directories-first -oghAt'
fi
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias mv='\mv -i' 
alias cp='cp -i' 
alias ln='ln -i'
alias rm='rm -I --preserve-root' 
alias rmd='rm -rf --preserve-root'
alias chmod='chmod --preserve-root' 
alias chown='chown --preserve-root' 
alias chgrp='chgrp --preserve-root'

alias histl="history | LC_ALL=C grep " 
alias findl="LC_ALL=C find . | LC_ALL=C grep " 
alias psl="ps aux | LC_ALL=C grep "
alias topcpu="ps -eo pcpu,pid,user,args | LC_ALL=C sort -k 1 -r | head -10"
alias diskl='LC_ALL=C lsblk -o NAME,SIZE,TYPE,MOUNTPOINT'
alias dir='dir --color=auto' 
alias vdir='vdir --color=auto'

# DIRECTORY NAVIGATION
alias ..="cd -- .."
alias ...="cd -- ../.."
alias ....="cd -- ../../.."
alias ~="cd -- $HOME"
alias cd-="cd -- -"

# https://snarky.ca/why-you-should-use-python-m-pip/
alias pip='python -m pip' py3='python3' py='python'

alias speedt='curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -'

# Dotfiles
# git clone --bare git@github.com:Ven0m0/dotfiles.git $HOME/.dotfiles
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
# dotfiles checkout

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
bind Space:magic-space
bind '"\C-o": kill-whole-line'
bind '"\C-a": beginning-of-line'
bind '"\C-e": end-of-line'
bind '"\e[1;5D": backward-word'
bind '"\e[1;5C": forward-word'
bind 'set enable-bracketed-paste off'
#──────────── Jumping ────────────
if has zoxide; then
  export _ZO_FZF_OPTS="--info=inline --tiebreak=index --layout=reverse --select-1 --exit-0"
  eval "$(LC_ALL=C zoxide init bash 2>/dev/null)" 2>/dev/null || true
  alias cd='z'
elif has enhancd; then
  export ENHANCD_FILTER="$HOME/.cargo/bin/sk:sk:fzf"
  alias cd='enhancd'
fi
#──────────── End ────────────
dedupe_path(){
  local IFS=: dir s; declare -A seen
  for dir in $PATH; do
    [[ -n $dir && -z ${seen[$dir]} ]] && seen[$dir]=1 && s="${s:+$s:}$dir"
  done
  [[ -n $s ]] && export PATH="$s"
}
dedupe_path
has systemctl && command systemctl --user import-environment PATH &>/dev/null
#──────────── Prompt 2 ────────────
configure_prompt(){
  if command -v starship &>/dev/null; then
    eval "$(LC_ALL=C starship init bash 2>/dev/null)" &>/dev/null; return
  fi
  local C_USER='\[\e[35m\]' C_HOST='\[\e[34m\]' YLW='\[\e[33m\]' \
        C_PATH='\[\e[36m\]' C_RESET='\[\e[0m\]' C_ROOT='\[\e[31m\]'
  local USERN HOSTL
  # Git
  local GIT_PS1_SHOWDIRTYSTATE=false GIT_PS1_OMITSPARSESTATE=true
  [[ "$EUID" -eq 0 ]] && USERN="${C_ROOT}\u${C_RESET}"
  [[ -n "$SSH_CONNECTION" ]] && HOSTL="${YLW}\h${C_RESET}"
  PS1="[${C_USER}\u${C_RESET}@${HOSTL}|${C_PATH}\w${C_RESET}] \$ "
  # Only add mommy if not in stealth mode and not already present in PROMPT_COMMAND
  if command -v mommy &>/dev/null && [[ "${stealth:-0}" -ne 1 ]] && [[ ${PROMPT_COMMAND:-} != *mommy* ]]; then
    PROMPT_COMMAND="LC_ALL=C mommy -1 -s \$?; ${PROMPT_COMMAND:-}" # mommy https://github.com/fwdekker/mommy
    # PROMPT_COMMAND="LC_ALL=C mommy \$?; ${PROMPT_COMMAND:-}" # Shell-mommy https://github.com/sleepymincy/mommy
  fi
}
configure_prompt
#──────────── Fetch ────────────
if [[ $SHLVL -le 2 ]]; then
  if [ "${stealth:-0}" -eq 1 ]; then
    has fastfetch && LC_ALL=C fastfetch --ds-force-drm --thread --detect-version false 2>/dev/null
  else
    if has hyfetch; then
      LC_ALL=C hyfetch -b fastfetch -m rgb -p transgender 2>/dev/null
    elif has fastfetch; then
      LC_ALL=C fastfetch --ds-force-drm --thread 2>/dev/null
    else
      LC_ALL=C hostnamectl 2>/dev/null
    fi
  fi
fi
#────────────────────────
