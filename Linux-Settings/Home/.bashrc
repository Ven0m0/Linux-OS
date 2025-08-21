# ~/.bashrc

[[ $- != *i* ]] && return
#──────────── Helpers ────────────
has(){ LC_ALL=C LANG=C command -v -- "$1" &>/dev/null; } # Check for command
hasname(){ local x; x=$(LC_ALL=C LANG=C type -P -- "$1") || return; printf '%s\n' "${x##*/}"; } # Basename of command
p(){ printf '%s\n' "$*" 2>/dev/null; } # Print-echo
pe(){ printf '%b\n' "$*" 2>/dev/null; } # Print-echo for color
_ifsource(){ [[ -f "$1" ]] && . -- "$1" 2>/dev/null; } # Source file if it exists
_prependpath(){ [[ -d "$1" ]] && [[ ":$PATH:" != *":$1:"* ]] && PATH="$1${PATH:+:$PATH}"; } # Only prepend if not already in PATH
#──────────── Sourcing ────────────
_ifsource "/etc/bashrc"
_ifsource "$HOME/.bash_aliases"
_ifsource "$HOME/.bash_functions"
_ifsource "$HOME/.fns"
_ifsource "$HOME/.funcs"
_ifsource "$HOME/.config/Bash/bashenv"
# Enable bash programmable completion features in interactive shells
_ifsource "/usr/share/bash-completion/bash_completion" || _ifsource "/etc/bash_completion"
#──────────── Stealth ────────────
#stealth=${stealth:-0}
stealth="1"
#──────────── Fetch ────────────
# fetch (precompute only if fastfetch exists; background + disown)
if has fastfetch; then
  fast_cmd=(fastfetch --detect-version false --users-myself-only --localip-compact --ds-force-drm --thread)
fi
if [ "${stealth:-0}" -eq 1 ]; then
  [[ ${#fast_cmd[@]:-0} -gt 0 ]] && fetch_cmd=("${fast_cmd[@]}")
else
  if has hyfetch; then
    fetch_cmd=(hyfetch -b fastfetch -m rgb -p transgender)
  elif [[ ${#fast_cmd[@]:-0} -gt 0 ]]; then
    fetch_cmd=("${fast_cmd[@]}")
  fi
fi
if (( ${#fetch_cmd[@]:-0} )); then
  LC_ALL=C LANG=C "${fetch_cmd[@]}" >/dev/null 2>&1 & disown 2>/dev/null || :
  unset fetch_cmd fast_cmd
fi
#──────────── Prompt ────────────
# PS1='[\u@\h|\w] \$' # bash-prompt-generator.org
HISTSIZE=10000 HISTFILESIZE=$HISTSIZE
HISTCONTROL="erasedups:ignoreboth"
HISTIGNORE="&:ls:[bf]g:help:clear:printf:exit:history:bash:fish:?:??"
HISTTIMEFORMAT='%F %T '
HISTFILE="$HOME/.bash_history"
PROMPT_DIRTRIM=2 PROMPT_COMMAND="history -a"
configure_prompt(){
  local C_USER='\[\e[35m\]' C_HOST='\[\e[34m\]' \
    C_PATH='\[\e[36m\]' C_RESET='\[\e[0m\]' C_ROOT='\[\e[31m\]' \
    USERN="${C_USER}\u${C_RESET}" HOSTL="${C_HOST}\h${C_RESET}" YLW='\[\e[33m\]'
  if has starship; then
    eval "$(LC_ALL=C LANG=C starship init bash 2>/dev/null)" &>/dev/null
  else
    [[ "$USER" = "root" ]] && USERN="${C_ROOT}\u${C_RESET}"
    [[ -z "$SSH_CONNECTION" ]] && HOSTL="${YLW}\h${C_RESET}"
    PS1="[${C_USER}\u${C_RESET}@${HOSTL}»${C_PATH}\w${C_RESET}] \$ "
  fi
  # Only add mommy if not in stealth mode and not already present in PROMPT_COMMAND
  if has mommy && [ "${stealth:-0}" -ne 1 ] && [[ $(echo "$PROMPT_COMMAND") != *"mommy"* ]]; then
	# Shell-mommy https://github.com/sleepymincy/mommy
    #PROMPT_COMMAND="mommy \$?; $PROMPT_COMMAND"
	# mommy https://github.com/fwdekker/mommy
    PROMPT_COMMAND="mommy -1 -s \$?; $PROMPT_COMMAND"
  fi
}
LC_ALL=C LANG=C configure_prompt 2>/dev/null
#──────────── Core ────────────
CDPATH=".:$HOME:/"
ulimit -c 0 &>/dev/null # disable core dumps
shopt -s histappend cmdhist checkwinsize dirspell cdable_vars\
         cdspell autocd hostcomplete no_empty_cmd_completion &>/dev/null
# Disable Ctrl-s, Ctrl-q
stty -ixon -ixoff -ixany &>/dev/null
# https://github.com/perlun/dotfiles/blob/master/profile
set +H # causes problems with git commit
# set -o vi # vi mode
#──────────── Env ────────────
_prependpath "$HOME/.local/bin"
_prependpath "$HOME/bin"
#export PATH # We export path in "dedupe_path"

# Fastest way to set valid editor with fallback
EDITOR="$(command -v micro 2>/dev/null)"; EDITOR="${EDITOR##*/}"; EDITOR="${EDITOR:-nano}"
export EDITOR VISUAL="$EDITOR" VIEWER="$EDITOR" GIT_EDITOR="$EDITOR" SYSTEMD_EDITOR="$EDITOR" FCEDIT="$EDITOR" SUDO_EDITOR="$EDITOR"

# https://wiki.archlinux.org/title/Locale
unset LC_ALL; export LANG="${LANG:-C.UTF-8}" LANGUAGE="en_US:en_DE:en:C:de_DE" LC_MEASUREMENT=C LC_COLLATE=C LC_CTYPE=C
germanloc="$(locale -a 2>/dev/null | LC_ALL=C \grep -qEi '^en_DE\.UTF-8$|^en_DE\.UTF8$' && echo en_DE.UTF-8 || (locale -a 2>/dev/null | LC_ALL=C \grep -qEi '^de_DE\.UTF-8$|^de_DE\.UTF8$' && echo de_DE || echo C))"
export LC_MONETARY="$germanloc" LC_TIME="$germanloc"

unset LC_ALL; locales=$(locale -a 2>/dev/null)
germanloc=$(echo "$locales" | LC_ALL=C grep -qEi '^en_DE\.UTF-8$|^en_DE\.UTF8$' && echo en_DE.UTF-8 || (echo "$locales" | LC_ALL=C grep -qEi '^de_DE\.UTF-8$|^de_DE\.UTF8$' && echo de_DE.UTF-8 || echo C))
# Export main locale and performance-friendly categories
export LANG="${LANG:-C.UTF-8}" \
       LANGUAGE="en_US:en:C:de_DE" \
       LC_MEASUREMENT=C \
       LC_COLLATE=C \
       LC_CTYPE=C \
       LC_MONETARY="${germanloc:-C.UTF-8}" \
       LC_TIME="${germanloc:-C.UTF-8}"

# Mimalloc & Jemalloc
export MALLOC_CONF="metadata_thp:auto,tcache:true,background_thread:true,percpu_arena:percpu,trust_madvise:enabled"
export _RJEM_MALLOC_CONF="$MALLOC_CONF"
# https://github.com/microsoft/mimalloc/blob/main/docs/environment.html
export MIMALLOC_VERBOSE=0 MIMALLOC_SHOW_ERRORS=0 MIMALLOC_SHOW_STATS=0 MIMALLOC_ALLOW_LARGE_OS_PAGES=1 MIMALLOC_PURGE_DELAY=25 MIMALLOC_ARENA_EAGER_COMMIT=2

# Delta pager
has delta && { export GIT_PAGER=delta; has batdiff || has batdiff.sh && export BATDIFF_USE_DELTA=true; }

if has bat; then
  export PAGER=bat BAT_STYLE=auto BAT_THEME=ansi BATPIPE=color GIT_PAGER="${GIT_PAGER:-bat}"
  alias cat="bat -spp --" bat="bat --color auto --" 2>/dev/null
  has batman && eval "$(batman --export-env 2>/dev/null)" 2>/dev/null
  has batgrep && alias batgrep="batgrep --rga -S --color 2>/dev/null" 2>/dev/null
elif has batcat; then
  export PAGER=batcat BAT_STYLE=auto BAT_THEME=ansi BATPIPE=color GIT_PAGER="${GIT_PAGER:-batcat}"
  alias cat="batcat -spp --" bat="batcat -s --color auto --"
elif has less; then
  export PAGER=less LESSHISTFILE="-" LESS='-FRXns --mouse --use-color --no-init' GIT_PAGER="${GIT_PAGER:-less}"
fi

if has less; then
  export LESS_TERMCAP_md=$'\e[01;31m' LESS_TERMCAP_me=$'\e[0m' LESS_TERMCAP_us=$'\e[01;32m' LESS_TERMCAP_ue=$'\e[0m' LESS_TERMCAP_so=$'\e[45;93m' LESS_TERMCAP_se=$'\e[0m'
  # Make less friendly for non-text input files
  has lesspipe && eval "$(SHELL=/bin/sh LC_ALL=C LANG=C lesspipe 2>/dev/null)" 2>/dev/null
fi

# XDG
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:=$HOME/.config}" \
  XDG_DATA_HOME="${XDG_DATA_HOME:=$HOME/.local/share}" \
  XDG_STATE_HOME="${XDG_STATE_HOME:=$HOME/.local/state}" \
  XDG_CACHE_HOME="${XDG_CACHE_HOME:=$HOME/.cache}"

export INPUTRC="$HOME/.inputrc"
export CURL_HOME="$HOME"

# Wget
if has wget; then
  [[ -f $HOME/.config/wget/wgetrc ]] && WGETRC="$HOME/.config/wget/wgetrc"
  export WGETRC="${WGETRC:-$HOME/wgetrc}"
  wgett() { command wget -cnv --hsts-file="$HOME/.cache/wget-hsts" "$@"; }
fi

if has cargo; then
  _ifsource "$HOME/.cargo/env"
  export CARGO_HOME="${HOME}/.cargo" RUSTUP_HOME="${HOME}/.rustup"
  _prependpath "${CARGO_HOME}/bin"
fi

# fd‑ignore file
if [[ -f $HOME/.ignore ]]; then
  export FD_IGNORE_FILE="${HOME}/.ignore"
elif [[ -f $HOME/.gitignore ]]; then
  export FD_IGNORE_FILE="${HOME}/.gitignore"
fi
export FIGNORE="argo.lock"

if has qt6ct; then
  export QT_QPA_PLATFORMTHEME='qt6ct'
elif has qt5ct; then
  export QT_QPA_PLATFORMTHEME='qt5ct'
fi
export QT_AUTO_SCREEN_SCALE_FACTOR=1 ELECTRON_OZONE_PLATFORM_HINT=auto ELECTRON_ENABLE_LOGGING=false ELECTRON_ENABLE_STACK_DUMPING=false \
  _JAVA_AWT_WM_NONREPARENTING=1 GTK_USE_PORTAL=1 \
  QSG_NO_VSYNC=1 _GL_THREADED_OPTIMIZATIONS=1 ZSTD_NBTHREADS=0

# export GSK_RENDERER=vulkan GSK_RENDERER=ngl

### Apps
# Wayland
if [[ ${XDG_SESSION_TYPE:-} == "wayland" ]]; then
  export GDK_BACKEND=wayland QT_QPA_PLATFORM=wayland SDL_VIDEODRIVER=wayland CLUTTER_BACKEND=wayland \
    MOZ_ENABLE_WAYLAND=1 MOZ_ENABLE_XINPUT2=1 QT_WAYLAND_DISABLE_WINDOWDECORATION=1
fi

# Proton/Wine
export MESA_DEBUG=0 MESA_NO_ERROR=1 \
  WINE_NO_WM_DECORATION=1 WINE_PREFER_SDL_INPUT=1 \
  PROTON_ENABLE_WAYLAND=1 PROTON_NO_WM_DECORATION=1 PROTON_PREFER_SDL_INPUT=1 PROTON_ENABLE_NVAPI=1 PROTON_ENABLE_NGX_UPDATER=1 PROTON_FSR4_UPGRADE=1

if has dircolors; then  
  eval "$(LC_ALL=C dircolors -b 2>/dev/null)" 2>/dev/null
else
  export LS_COLORS='no=00:fi=00:di=00;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.tga=01;35:*.tiff=01;35:*.png=01;35:*.mpeg=01;35:*.avi=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:*.xml=00;31:'
fi

# gpg (for Github) https://github.com/alfunx/.dotfiles/blob/master/.profile
# https://www.reddit.com/r/programming/comments/109rjuj/how_setting_the_tz_environment_variable_avoids
export GPG_TTY="$(tty)" TZ="Europe/Berlin" CLICOLOR=1

# Build env
has sccache && export SCCACHE_DIRECT=1 SCCACHE_ALLOW_CORE_DUMPS=0 SCCACHE_CACHE_ZSTD_LEVEL=6 SCCACHE_CACHE_SIZE=8G RUSTC_WRAPPER=sccache
has ccache && export CCACHE_COMPRESS=true CCACHE_COMPRESSLEVEL=3 CCACHE_INODECACHE=true
has gix && export GITOXIDE_CORE_MULTIPACKINDEX=true GITOXIDE_HTTP_SSLVERSIONMAX=tls1.3 GITOXIDE_HTTP_SSLVERSIONMIN=tls1.2

# Python opt's
export PYTHONOPTIMIZE=2 PYTHONIOENCODING='UTF-8' PYTHON_JIT=1 PYENV_VIRTUALENV_DISABLE_PROMPT=1
#──────────── Fuzzy finders ────────────
fuzzy_finders() {
  if has fd; then
  	FIND_CMD='fd -tf -F --hidden --exclude .git --exclude node_modules --exclude target'
  elif has rg; then
	FIND_CMD='rg --files --hidden --glob "!.git" --glob "!node_modules" --glob "!target"'
  else
  	FIND_CMD='find . -type f ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*"'
  fi
  export FZF_DEFAULT_COMMAND="$FIND_CMD" \
    FZF_DEFAULT_OPTS="--info=inline --layout=reverse --tiebreak=index --height=70%" \
    FZF_CTRL_T_COMMAND="$FIND_CMD" \
    FZF_CTRL_T_OPTS="--select-1 --exit-0 --preview 'bat --color=always --style=numbers --line-range=:250 {} || cat {} 2>/dev/null'" \
    FZF_CTRL_R_OPTS="--select-1 --exit-0 --no-sort --exact --preview 'echo {}' --preview-window down:3:hidden:wrap --bind '?:toggle-preview'" \
	FZF_ALT_C_OPTS="--select-1 --exit-0 --walker-skip .git,node_modules,target --preview 'tree -C {} | head -200'" \
    FZF_COMPLETION_OPTS='--border --info=inline --tiebreak=index' \
    FZF_COMPLETION_PATH_OPTS="--info=inline --tiebreak=index --walker file,dir,follow,hidden" \
    FZF_COMPLETION_DIR_OPTS="--info=inline --tiebreak=index --walker dir,follow"
  [[ ! -d $HOME/.config/bash/completions ]] && mkdir -p -- "$HOME/.config/bash/completions" &>/dev/null
  if has fzf; then
    unalias fzf &>/dev/null
	[[ -f /usr/share/fzf/key-bindings.bash ]] && . "/usr/share/fzf/key-bindings.bash" 2>/dev/null
    if [[ ! -f $HOME/.config/bash/completions/fzf_completion.bash ]]; then
	  fzf --bash 2>/dev/null >|"$HOME/.config/bash/completions/fzf_completion.bash"
    fi
    . $HOME/.config/bash/completions/fzf_completion.bash 2>/dev/null
  fi
  if has sk; then
    export SKIM_DEFAULT_COMMAND="$FIND_CMD" SKIM_DEFAULT_OPTIONS="$FZF_DEFAULT_OPTS"
	alias fzf='sk ' &>/dev/null
    [[ -f /usr/share/skim/key-bindings.bash ]] && . "/usr/share/skim/key-bindings.bash" 2>/dev/null
    if [[ ! -f $HOME/.config/bash/completions/sk_completion.bash ]]; then
	  sk --shell bash 2>/dev/null >|"$HOME/.config/bash/completions/sk_completion.bash"
    fi
    . $HOME/.config/bash/completions/sk_completion.bash 2>/dev/null
  fi
}
LC_ALL=C LANG=C fuzzy_finders 2>/dev/null
#──────────── Completions ────────────
# command -v fzf &>/dev/null && eval "$(fzf --bash 2>/dev/null)" 2>/dev/null
# command -v sk &>/dev/null && eval "$(sk --shell bash 2>/dev/null)" 2>/dev/null
complete -cf sudo 2>/dev/null
has pay-respects && eval "$(pay-respects bash 2>/dev/null)" 2>/dev/null

# Ghostty
[[ $TERM == xterm-ghostty && -e "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash" ]] && . "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash" 2>/dev/null

# Wikiman
# [[ has wikiman && -f /usr/share/wikiman/widgets/widget.bash ]] && . "/usr/share/wikiman/widgets/widget.bash" 2>/dev/null
#──────────── Functions ────────────
# Having to set a new script as executable always annoys me.
runch(){
  shopt -u nullglob nocaseglob; local s="$1"
  [[ $s ]] || { printf 'runch: missing script argument\nUsage: runch <script>\n' >&2; return 2; }
  [[ -f $s ]] || { printf 'runch: file not found: %s\n' "$s" >&2; return 1; }
  command chmod u+x -- "$s" 2>/dev/null || { printf 'runch: cannot make executable: %s\n' "$s" >&2; return 1; }
  [[ $s == */* ]] && "$s" || "./$s"
}

# ls or cat
sel(){
  local p="${1:-.}"
  [[ -e "$p" ]] || { printf 'sel: not found: %s\n' "$p" >&2; return 1; }
  if [[ -d "$p" ]]; then
    if command -v eza &>/dev/null; then
      LC_ALL=C LANG=C command eza -al --color=auto --group-directories-first --icons=auto --no-time --no-git --smart-group --no-user --no-permissions -- "$p"
    else
      LC_ALL=C LANG=C command ls -a --color=auto --group-directories-first -- "$p"
    fi
  elif [[ -f "$p" ]]; then
    if command -v bat &>/dev/null; then
      local bn
      bn=$(basename -- "$p")
      # let bat handle paging; show only basename as file-name
      LC_ALL=C LANG=C command bat -sp --color auto --file-name="$bn" -- "$p"
    else
      LC_ALL=C LANG=C command cat -s -- "$p"
    fi
  else
    printf 'sel: not a file/dir: %s\n' "$p" >&2; return 1
fi
}

sudo-command-line() {
  echo "toggle sudo at the beginning of the current or the previous command by hitting the ESC key twice"
  [[ ${#READLINE_LINE} -eq 0 ]] && READLINE_LINE=$(fc -l -n -1 | xargs)
  if [[ $READLINE_LINE == sudo\ * ]]; then
	READLINE_LINE="${READLINE_LINE#sudo }"
  else
	READLINE_LINE="sudo $READLINE_LINE"
  fi
  READLINE_POINT="${#READLINE_LINE}"
}
bind -x '"\e\e": sudo-command-line'

gcom(){ local LC_ALL=C LANG=C; command git add . && command git commit -m "$1"; }
lazyg(){ local LC_ALL=C LANG=C; command git add . && command git commit -m -- "$1" && command git push; }
navibestmatch(){ local LC_ALL=C LANG=C; command navi --query "$1" --best-match; }
symbreak(){ local LC_ALL=C LANG=C; command find -L "${1:-.}" -type l; }

has hyperfine && hypertest(){ LC_ALL=C command hyperfine -w 25 -m 50 -i -- "$@"; }

touch(){ local LC_ALL=C LANG=C; command mkdir -p "$(dirname -- "$1")" && command touch -- "$1" }
#──────────── Aliases ────────────
# Enable aliases to be sudo’ed
alias sudo="sudo " sudo-rs="sudo-rs " doas="doas "
alias mkdir='mkdir -p'
alias ed='$EDITOR' mi='$EDITOR' smi='sudo $EDITOR'
# Rerun last cmd as sudo
#please(){ local last; last=$(fc -ln -1 2>/dev/null) || return; command sudo bash -c -- "$last"; }
alias please='sudo !!'

alias pacman='sudo pacman --noconfirm --needed --color=auto' paru='paru --skipreview --noconfirm --needed'

alias cls='clear' c='clear'
alias ping='ping -c 4' # Stops ping after 4 requests
alias mount='mount | column -t' # human readable format
alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'

if has eza; then
  alias ls='LC_ALL=C \eza -al --color=auto --group-directories-first --icons=auto --no-time --no-git --smart-group --no-user --no-permissions'
  alias la='\eza -a --color=auto --group-directories-first --icons=auto --smart-group'
  alias ll='\eza -al --color=auto --group-directories-first --icons=auto --no-time --no-git --smart-group'
  alias lt='\eza -aT --color=auto --group-directories-first --icons=auto --smart-group'
else
  alias ls='LC_ALL=C \ls --color=auto --group-directories-first'
  alias la='\ls --color=auto --group-directories-first -a'
  alias ll='\ls --color=auto --group-directories-first -lh'
  alias lt='\ls --color=auto --group-directories-first -lhAR'
fi

if has rg; then
  alias grep='LC_ALL=C \rg -S --color=auto'
  alias fgrep='\rg -SF --color=auto'
  alias egrep='\rg -Se --color=auto'
  alias rg='LC_ALL=C \rg -NFS --mmap --no-unicode --engine=default --no-stats --color=auto'
elif has ugrep; then
  alias grep='LC_ALL=C \ugrep --color=auto'
  alias fgrep='\ugrep -F --color=auto'
  alias egrep='\ugrep -E --color=auto'
  alias ugrep='LC_ALL=C \ugrep --color=auto'
  alias ug='LC_ALL=C \ug -sjFU --color=auto'
else
  alias grep='LC_ALL=C \grep --color=auto'
  alias fgrep='\fgrep --color=auto'
  alias egrep='\egrep --color=auto'
fi

alias mv='\mv -i' cp='cp -i' ln='ln -i'
alias rm='\rm -I --preserve-root' rmd='\rm -rf --preserve-root'
alias chmod='\chmod --preserve-root' chown='\chown --preserve-root' chgrp='\chgrp --preserve-root'

alias h="history | LC_ALL=C grep " f="LC_ALL=C find . | LC_ALL=C grep "
# Search running processes
alias p="ps aux | LC_ALL=C grep "
alias topcpu="ps -eo pcpu,pid,user,args | LC_ALL=C sort -k 1 -r | head -10"
alias disk='LC_ALL=C LANG=C lsblk -o NAME,SIZE,TYPE,MOUNTPOINT'
alias dir='dir --color=auto' vdir='vdir --color=auto'

# fd (find replacement)
has fd && alias find='\fd'
# Procs (ps replacement)
has procs && alias ps='procs'

# Dust (du replacement)
if has dust; then
  alias du='dust'
  dustd(){ local LC_ALL=C LANG=C; command dust -bP -T "$(LC_ALL=C LANG=C nproc || echo 1)" -- "${1:-.}" 2>/dev/null; }
fi

# Bottom (top replacement)
has btm && alias top='btm' htop='btm'

# DIRECTORY NAVIGATION
alias ..="cd -- .."
alias ...="cd -- ../.."
alias ....="cd -- ../../.."
alias ~="cd -- $HOME"
alias cd-="cd -- -"
alias git..='cd $(LC_ALL=C LANG=C git rev-parse --show-toplevel 2>/dev/null || echo ".")'

# https://snarky.ca/why-you-should-use-python-m-pip/
alias pip='python -m pip' py3='python3' py='python'

alias speedt='curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -'
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
# Fix bracket paste
bind 'set enable-bracketed-paste off'
[[ -t 0 ]] && printf '\e[?2004l' >/dev/tty
# Ctrl+A = beginning-of-line
# Ctrl+E = end-of-line
# Ctrl+Left / Ctrl+Right word movement
bind '"\C-a": beginning-of-line'
bind '"\C-e": end-of-line'
bind '"\e[1;5D": backward-word'
bind '"\e[1;5C": forward-word'
#──────────── Jumping ────────────
if has zoxide; then
  export _ZO_FZF_OPTS="--info=inline --tiebreak=index --layout=reverse --select-1 --exit-0"
  eval "$(LC_ALL=C LANG=C zoxide init bash 2>/dev/null)" 2>/dev/null; alias cd='z'
elif has enhancd; then
  export ENHANCD_FILTER="$HOME/.cargo/bin/sk:sk:fzf:fzy"; alias cd='enhancd'
fi
#──────────── End ────────────
# Deduplicate PATH (preserve order)
dedupe_path(){
  local IFS=: dir s; declare -A seen
  for dir in $PATH; do
    [[ -n $dir && -z ${seen[$dir]} ]] && seen[$dir]=1 && s="${s:+$s:}$dir"
  done
  [[ -n $s ]] && export PATH="$s"
}
LC_ALL=C LANG=C dedupe_path 2>/dev/null
# Import PATH into systemd user environment if systemctl exists
if has systemctl; then
  command systemctl --user import-environment PATH &>/dev/null || :
fi
