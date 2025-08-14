# ~/.bashrc

#──────────── Only for interactive shells────────────
[[ $- != *i* ]] && return
#──────────── Helpers────────────
# Check for command
has() { command -v "$1" &>/dev/null; }
# Print-echo
p() { printf "%s\n" "$@"; }
# Print-echo for color
pe() { printf "%b\n" "$@"; }
# ─── Sourcing ───────────────────────────────────────────
[[ -f /etc/bashrc ]] && . /etc/bashrc
# Enable bash programmable completion features in interactive shells
if [[ -f /usr/share/bash-completion/bash_completion ]]; then
	. /usr/share/bash-completion/bash_completion
elif [[ -f /etc/bash_completion ]]; then
	. /etc/bash_completion
fi
[[ -f $HOME/.config/bash/bashenv.env ]] && . "$HOME/.config/Bash/bashenv"

# [[ -f $HOME/.fns]] && . "$HOME/.fns"
# [[ -f $HOME/.funcs]] && . "$HOME/.funcs"
#──────────── Fetch────────────
if has hyfetch; then
  fetch="hyfetch -b fastfetch -m rgb -p transgender"
elif has fastfetch
  fetch="fastfetch --detect-version false --users-myself-only --localip-compact --ds-force-drm --thread"
fi
LC_ALL=C LANG=C.UTF-8 "$fetch" 2>/dev/null; unset fetch
#──────────── Prompt────────────
# PS1='[\u@\h|\w] \$' # bash-prompt-generator.org
# PS1="\w \[\e[31m\]»\[\e[33m\]»\[\e[32m\]»\[\e[0m\] "

HISTFILESIZE=10000 HISTSIZE=500
HISTCONTROL="erasedups:ignoreboth"
HISTIGNORE="&:ls:[bf]g:help:clear:exit:history:bash:fish:?:??"
HISTTIMEFORMAT='%F %T '
HISTFILE=$HOME/.bash_history
PROMPT_DIRTRIM=2
PROMPT_COMMAND="history -a"

configure_prompt() {
  local GIT_PROMPT='' \
        C_USER='\[\e[35m\]' C_HOST='\[\e[34m\]' \
        C_PATH='\[\e[36m\]' C_RESET='\[\e[0m\]'
  if has starship; then
    eval "$(LC_ALL=C LANG=C.UTF-8 starship init bash 2>/dev/null)" &>/dev/null
  else
    PS1="[${C_USER}\u${C_RESET}@${C_HOST}\h${C_RESET}»${C_PATH}\w${C_RESET}]$GIT_PROMPT \$ "
    __update_git_prompt() {
      [[ $PWD == ${__git_prompt_prev_pwd:-} ]] && return
      __git_prompt_prev_pwd=$PWD
      local root name
      root=$(LC_ALL=C LANG=C.UTF-8 git rev-parse --show-toplevel 2>/dev/null) || { GIT_PROMPT=; return; }
      name=${root##*/}
      GIT_PROMPT=" \[\e[35m\]>$name\[\e[0m\]"
    }
    [[ ";$PROMPT_COMMAND" != *";"__update_git_prompt* ]] && \
      PROMPT_COMMAND="__update_git_prompt; $PROMPT_COMMAND"
  fi
 if has mommy && [[ $(echo $PROMPT_COMMAND) != *"mommy"* ]]; then
    # Shell-mommy https://github.com/sleepymincy/mommy
    #PROMPT_COMMAND="LC_ALL=C LANG=C.UTF-8 mommy \$?; $PROMPT_COMMAND" SHELL_MOMMY_ONLY_NEGATIVE=1
    # mommy https://github.com/fwdekker/mommy
    PROMPT_COMMAND="LC_ALL=C LANG=C.UTF-8 mommy -1 -s \$?; $PROMPT_COMMAND"
  fi
}
LC_ALL=C LANG=C.UTF-8 configure_prompt 2>/dev/null
#────────────Core────────────
unset LC_ALL; export LC_CTYPE=C LC_COLLATE=C
if locale -a | grep -q "^en_US\.utf8$"; then
  export LANG="en_US.UTF-8" LANGUAGE="en_US"
else
  export LANG='C.UTF-8'
fi
export CDPATH=".:$HOME"
ulimit -c 0 &>/dev/null # disable core dumps
shopt -s nullglob globstar histappend cmdhist checkwinsize \
         dirspell cdspell autocd hostcomplete no_empty_cmd_completion &>/dev/null
shopt -u mailwarn &>/dev/null; unset MAILCHECK # Bash-it
# Disable Ctrl-s, Ctrl-q
stty -ixon -ixoff -ixany &>/dev/null
# https://github.com/perlun/dotfiles/blob/master/profile
# causes problems with git commit
set +H
# Enforce default umask
umask 0022

# XDG
export \
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:=$HOME/.config}" \
  XDG_DATA_HOME="${XDG_DATA_HOME:=$HOME/.local/share}" \
  XDG_STATE_HOME="${XDG_STATE_HOME:=$HOME/.local/state}" \
  XDG_CACHE_HOME="${XDG_CACHE_HOME:=$HOME/.cache}"

# Pi3 fix low power message warning
[[ $TERM != xterm-256color && $TERM != xterm-ghostty ]] && { setterm --msg off &>/dev/null; setterm --bfreq 0 &>/dev/null; }
setterm --linewrap on &>/dev/null

#────────────Env────────────
[[ -f $HOME/.cargo/env ]] && . "$HOME/.cargo/env"
# Bins
[[ -d "${HOME}/bin" && ":$PATH:" != *":${HOME}/bin:"* ]] && export PATH="${HOME}/bin${PATH:+:$PATH}"

_prependpath() {
    # Only prepend if not already in PATH
    [ -d "$1" ] && [ ":$PATH:" != *":$1:"* ] && PATH="$1${PATH:+:$PATH}"
}
_prependpath "$HOME/.local/bin"
_prependpath "$HOME/bin"
export PATH

# Make less more friendly for non-text input files, see lesspipe(1)
[[ -x /usr/bin/lesspipe ]] && eval "$(SHELL=/bin/sh lesspipe)"

# Wget
if [[ -f "$HOME/.config/wget/wgetrc" ]]; then
  export WGETRC="${WGETRC:=${XDG_CONFIG_HOME:-$HOME/.config}/wget/wgetrc}"
elif [[ -f "$HOME/wgetrc" ]]; then
  export WGETRC="${WGETRC:=${XDG_CONFIG_HOME:-$HOME}/wgetrc}"
fi
# Enable settings for wget
has wget && wget() { command wget-cnv --hsts-file="${XDG_CACHE_HOME:-$HOME/.cache}/wget-hsts" "$@" }

if has micro; then
  export EDITOR=micro VISUAL=micro
else
  export EDITOR=nano VISUAL=name
fi
export VIEWER="$EDITOR" GIT_EDITOR="$EDITOR" SYSTEMD_EDITOR="$EDITOR" FCEDIT="$EDITOR" SUDO_EDITOR="$EDITOR"
git config --global core.editor "$EDITOR" &>/dev/null
alias nano='nano -/ ' # Nano modern keybinds
has curl && export CURL_HOME="$HOME"

if has delta; then
  export GIT_PAGER=delta
  if has batdiff || has batdiff.sh; then
    export BATDIFF_USE_DELTA=true
  fi
fi

has batpipe && export BATPIPE=color
if has bat; then
  export PAGER=bat BAT_STYLE="auto"
  export GIT_PAGER="${GIT_PAGER:=bat}"
  alias cat="bat -pp " bat="bat --color auto "
elif has batcat; then
  export PAGER=batcat BAT_STYLE="auto"
  export GIT_PAGER="${GIT_PAGER:=batcat}"
  alias cat="batcat -pp " bat="batcat --color auto "
elif has less; then
  export PAGER=less \
         LESSHISTFILE="-" \
         LESS='-FRXns --mouse --use-color --no-init'
  export GIT_PAGER="${GIT_PAGER:=less}"
fi

# fd‑ignore file
if [[ -f $HOME/.ignore ]]; then
  export FD_IGNORE_FILE="$HOME/.ignore"
elif [[ -f $HOME/.gitignore ]]; then
  export FD_IGNORE_FILE="$HOME/.gitignore"
fi
export FIGNORE=argo.lock

if has qt6ct; then
	export QT_QPA_PLATFORMTHEME='qt6ct'
elif has qt5ct; then
  export QT_QPA_PLATFORMTHEME='qt5ct'
fi

export CLICOLOR=1
export LS_COLORS='no=00:fi=00:di=00;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.tga=01;35:*.tiff=01;35:*.png=01;35:*.mpeg=01;35:*.avi=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:*.xml=00;31:'

### Apps
# Wayland
if [[ ${XDG_SESSION_TYPE:-} == "wayland" ]]; then
  export GDK_BACKEND=wayland
  export QT_QPA_PLATFORM=wayland
  export SDL_VIDEODRIVER=wayland
  export MOZ_ENABLE_WAYLAND=1
  export MOZ_ENABLE_XINPUT2=1
  export _JAVA_AWT_WM_NONREPARENTING=1
  export ELECTRON_OZONE_PLATFORM_HINT=auto
  # To use KDE file dialog with firefox https://daniele.tech/2019/02/how-to-execute-firefox-with-support-for-kde-filepicker/
  export GTK_USE_PORTAL=1
fi

# gpg (for Github) https://github.com/alfunx/.dotfiles/blob/master/.profile
export GPG_TTY="$(tty)"
# https://www.reddit.com/r/programming/comments/109rjuj/how_setting_the_tz_environment_variable_avoids/
export TZ=$(readlink -f /etc/localtime | cut -d/ -f 5-)

# Build env
if has sccache; then
  export SCCACHE_DIRECT=1 SCCACHE_ALLOW_CORE_DUMPS=0 \
  		 SCCACHE_CACHE_ZSTD_LEVEL=6 SCCACHE_CACHE_SIZE=8G \
  		 RUSTC_WRAPPER=sccache
fi
has ccache && export CCACHE_COMPRESS=true CCACHE_COMPRESSLEVEL=3 CCACHE_INODECACHE=true
has gix && export GITOXIDE_CORE_MULTIPACKINDEX=true GITOXIDE_HTTP_SSLVERSIONMAX=tls1.3 GITOXIDE_HTTP_SSLVERSIONMIN=tls1.2
has rust-parallel && export PROGRESS_STYLE=simple

if has cargo; then
  export CARGO_HOME="${HOME}/.cargo" RUSTUP_HOME="${HOME}/.rustup"
  export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
  export CARGO_HTTP_SSL_VERSION=tlsv1.3 CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
  export RUST_LOG=off RUST_BACKTRACE=0
fi
# Python opt's
export PYTHONOPTIMIZE=2 PYTHONIOENCODING='UTF-8' PYTHON_JIT=1 PYENV_VIRTUALENV_DISABLE_PROMPT=1
export GOPROXY="direct" # no fancy google cache for go
#────────────Fuzzy finders────────────
fuzzy_finders() {
	if has fd; then
  		FIND_CMD='fd -tf -F --hidden --exclude .git --exclude node_modules --exclude target'
	elif has rg; then
	  FIND_CMD='rg --files --hidden --glob "!.git" --glob "!node_modules" --glob "!target"'
	else
  		FIND_CMD='find . -type f ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*"'
	fi
	export FZF_DEFAULT_COMMAND="$FIND_CMD" \
       	   FZF_DEFAULT_OPTS="--info=inline --tiebreak=index --layout=reverse-list --height=70%" \
       	   FZF_CTRL_T_COMMAND="$FIND_CMD" \
       	   FZF_CTRL_T_OPTS="--select-1 --exit-0  --preview '(bat --color=always --style=numbers --line-range=:250 {} || cat {}) 2>/dev/null)'"
       	   FZF_CTRL_R_OPTS='--no-sort --exact' \
       	   FZF_COMPLETION_OPTS='--border --info=inline --tiebreak=index' \
      	   FZF_COMPLETION_PATH_OPTS='--info=inline --walker file,dir,follow,hidden' \
           FZF_COMPLETION_DIR_OPTS='--info=inline --walker dir,follow'
	if has fzf; then
	  unalias fzf
	fi
	if has sk; then
		export SKIM_DEFAULT_COMMAND="$FIND_CMD" \
           SKIM_DEFAULT_OPTIONS="$FZF_DEFAULT_OPTS"
	  alias fzf='sk '
	fi
}

#────────────Completions────────────
complete -cf sudo
# Ensure completion directory exists
COMPDIR="$HOME/.config/bash/completions"
mkdir -p "$COMPDIR"
for tool in fzf sk; do
  has "$tool" || continue
  comp="$COMPDIR/${tool}_completion.bash"
  [[ -f $comp ]] || {
    [[ $tool == fzf ]] && "$tool" --bash 2>/dev/null >|"$comp"
    [[ $tool == sk  ]] && "$tool" --shell bash 2>/dev/null >|"$comp"
  }
    . "$comp" 2>/dev/null || {
      [[ $tool == fzf ]] && . <("$tool" --bash 2>/dev/null)
      [[ $tool == sk  ]] && . <("$tool" --shell bash 2>/dev/null)
    }
done; unset tool comp COMPDIR
# command -v fzf &>/dev/null && eval "$(fzf --bash 2>/dev/null)"
# command -v sk &>/dev/null && . <(sk --shell bash 2>/dev/null)
has pay-respects && eval "$(pay-respects bash 2>/dev/null)"
has batman && eval "$(batman --export-env 2>/dev/null)"
has batgrep && alias batgrep="batgrep --rga -S --color "

# Ghostty
[[ $TERM == xterm-ghostty && -e "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash" ]] && builtin . "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash"

# Wikiman
has wikiman && . /usr/share/wikiman/widgets/widget.bash
# ─── Functions ─────────────────────────────────────────────
# which() { command -v "$1" 2>/dev/null || return 1; }
alias which="command -v "

# Having to set a new script as executable always annoys me.
runch() {
  # Args
  local s=$1
  if [[ -z $s ]]; then
      printf 'chrun: missing script argument\nUsage: chrun <script>\n' >&2
      return 2
  fi
  # Try to chmod, silencing stderr; bail if it fails
  chmod u+x -- "$s" 2>/dev/null || {
      printf 'chrun: cannot make executable: %s\n' "$s" >&2
      return 1
  }
  # Exec: if name contains a slash, run as-is; otherwise prefix "./"
  case "$s" in
      */*) exec "$s"   ;;
      *)   exec "./$s" ;;
  esac
}

gcom() {
  git add .
  git commit -m "$1"
}
lazyg() {
  git add .
  git commit -m "$1"
  git push
}

#────────────Aliases────────────
# Enable aliases to be sudo’ed
alias sudo="\sudo "
alias doas="\doas "
alias sudo-rs="\sudo-rs "
alias mkdir="mkdir -p "
alias ed='$EDITOR'
alias mi='$EDITOR'
alias smi='sudo $EDITOR'
# alias smi='sudo -E ${$EDITOR:=$(command -v micro)'

# Rerun last cmd as sudo
please() { sudo "$(fc -ln -1)" }

alias clear "printf '\e[3J\e[H\e[2J\e[m'" c='clear'
alias ping='ping -c 4' # Stops ping after 4 requests
alias mount='mount | column -t' # human readable format
alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'

if has eza; then
  alias ls='eza -al --color=always --group-directories-first --icons'
  alias la='eza -a --color=always --group-directories-first --icons'
  alias ll='eza -l --color=always --group-directories-first --icons'
  alias lt='eza -aT --color=always --group-directories-first --icons'
else
  alias ls='ls --color=auto --group-directories-first'
  alias la='ls --color=auto --group-directories-first -a'
  alias ll='ls --color=auto --group-directories-first -lh'
  alias lt='ls --color=auto --group-directories-first -lhAR'
fi

if has ugrep; then
  alias grep='ugrep --color=auto'
  alias egrep='ugrep -E --color=auto'
  alias fgrep='ugrep -F --color=auto'
if has rg; then
  alias grep='rg --no-line-number'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
  alias rg='rg --no-stats --color=auto'
else
  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

alias mv='mv -i'
alias cp='cp -i'
alias ln='ln -i'
alias rm='rm -I --preserve-root'
alias rmd='rm -rfv --preserve-root'
alias chmod='chmod --preserve-root'

alias h="history | grep "
alias f="find . | grep "
# Search running processes
alias p="ps aux | grep "
alias topcpu="/bin/ps -eo pcpu,pid,user,args | sort -k 1 -r | head -10"

# fd (find replacement)
has fd && alias find='fd'

# Procs (ps replacement)
has procs && alias ps='procs'

# Dust (du replacement)
has dust && alias du='dust'

# Bottom (top replacement)
has btm && alias top='btm' htop='btm'

# Duf (df replacement)
has duf && alias df='duf'

alias dir='dir --color=auto'
alias vdir='vdir --color=auto'

# DIRECTORY NAVIGATION
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias ~="cd ~"
alias -- -="cd -"  # Go back to previous directory

#────────────Bindings (readline)────────────
bind 'set completion-query-items 150'
bind 'set page-completions off'
bind 'set show-all-if-ambiguous on'
bind 'set show-all-if-unmodified on'
bind 'set menu-complete-display-prefix on'
bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind 'set mark-directories on'[
bind "set mark-symlinked-directories on"
bind "set bell-style none"
bind 'set skip-completed-text on'
bind 'set colored-stats on'
bind 'set colored-completion-prefix on'
bind Space:magic-space
bind '"\C-o": kill-whole-line'
# Bash 5.3
bind 'set timeout 500'
# Fix bracket paste
bind 'set enable-bracketed-paste off'

# Ctrl+A = beginning-of-line
# Ctrl+E = end-of-line
# Ctrl+Left / Ctrl+Right word movement
bind '"\C-a": beginning-of-line'
bind '"\C-e": end-of-line'
bind '"\e[1;5D": backward-word'
bind '"\e[1;5C": forward-word'

#────────────Jumping────────────
if has zoxide; then
  export _ZO_FZF_OPTS="--info=inline --tiebreak=index --layout=reverse-list --select-1 --exit-0"
  eval "$(zoxide init bash)"
  alias cd='z'
elif has enhancd; then
  export ENHANCD_FILTER="$HOME/.cargo/bin/sk:sk:fzf:fzy"
  alias cd='enhancd'
fi
#────────────End────────────
# Deduplicate PATH (preserve order)
dedupe_path(){ local IFS=: dir s; if ((BASH_VERSINFO[0]>=4)); then declare -A seen; for dir in $PATH; do [[ $dir && -z ${seen[$dir]} ]] && seen[$dir]=1 && s=${s:+$s:}$dir; done; else for dir in $PATH; do [[ $dir && :$s: != *":$dir:"* ]] && s=${s:+$s:}$dir; done; fi; PATH=$s; export PATH; }
dedupe_path
