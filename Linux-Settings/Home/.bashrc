# ~/.bashrc

# ─── Only for interactive shells ───────────────────────────────────────────
[[ $- != *i* ]] && return
# ─── Sourcing ───────────────────────────────────────────
if [[ -f /etc/bashrc ]]; then
	. /etc/bashrc
fi
# Enable bash programmable completion features in interactive shells
if [[ -f /usr/share/bash-completion/bash_completion ]]; then
	. /usr/share/bash-completion/bash_completion
elif [[ -f /etc/bash_completion ]]; then
	. /etc/bash_completion
fi
if [[ -f $HOME/.config/bash/bashenv.env ]]; then
. "$HOME/.config/Bash/bashenv"
fi
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
export LC_CTYPE=C LC_COLLATE=C LANG="${LANG:-C.UTF-8}"; unset LC_ALL
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
# Disable Ctrl-s, Ctrl-q
stty -ixon

# XDG
export HOME \
       XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config} \
       XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share} \
       XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state} \
       XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}

# Pi3 fix low power message warning
[[ $TERM != xterm-256color && $TERM != xterm-ghostty ]] && { setterm --msg off; setterm --bfreq 0; }
setterm --linewrap on

# ─── Sourcing ──────────────────────────────────────────────
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
# Bins
[[ -d "${HOME}/bin" && ":$PATH:" != *":${HOME}/bin:"* ]] && export PATH="${HOME}/bin:${PATH}"

# ─── Environment ─────────────────────────────────────────────────────────
if command -v micro &>/dev/null; then
  export EDITOR=micro VISUAL=micro
else
  export EDITOR=nano VISUAL=name
fi
git config --global core.editor "$EDITOR" 2>/dev/null
export VIEWER="$EDITOR" GIT_EDITOR="$EDITOR" SYSTEMD_EDITOR="$EDITOR" FCEDIT="$EDITOR" SUDO_EDITOR="$EDITOR"
alias nano='nano -/ ' # Nano modern keybinds
command -v curl &>/dev/null && export CURL_HOME="$HOME"
command -v delta &>/dev/null && export GIT_PAGER=delta
command -v batpipe &>/dev/null && export BATPIPE=color
if command -v bat &>/dev/null; then
  export PAGER=bat BAT_STYLE="auto"
  alias cat='bat -pp ' bat='bat --color auto '
  : "${GIT_PAGER:=bat}"
elif command -v less &>/dev/null; then
  export PAGER=less \
         LESSHISTFILE="-" \
         LESS='-FRXns --mouse --use-color --no-init'
  : "${GIT_PAGER:=less}"
fi
# fd‑ignore file
if [[ -f $HOME/.ignore ]]; then
  export FD_IGNORE_FILE="$HOME/.ignore"
elif [[ -f $HOME/.gitignore ]]; then
  export FD_IGNORE_FILE="$HOME/.gitignore"
fi
export FIGNORE=argo.lock

if command -v qt6ct
	export QT_QPA_PLATFORMTHEME='qt6ct'
elif command -v qt5ct
  export QT_QPA_PLATFORMTHEME='qt5ct'
fi

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
if command -v sccache &>/dev/null; then
  export SCCACHE_DIRECT=1 SCCACHE_ALLOW_CORE_DUMPS=0 \
  		 SCCACHE_CACHE_ZSTD_LEVEL=6 SCCACHE_CACHE_SIZE=8G \
  		 RUSTC_WRAPPER=sccache
fi
command -v ccache &>/dev/null && export CCACHE_COMPRESS=true CCACHE_COMPRESSLEVEL=3 CCACHE_INODECACHE=true
command -v gix &>/dev/null && export GITOXIDE_CORE_MULTIPACKINDEX=true GITOXIDE_HTTP_SSLVERSIONMAX=tls1.3 GITOXIDE_HTTP_SSLVERSIONMIN=tls1.2
command -v rust-parallel &>/dev/null && export PROGRESS_STYLE=simple

if command -v cargo &>/dev/null; then
  export CARGO_HOME="${HOME}/.cargo" RUSTUP_HOME="${HOME}/.rustup"
  export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
  export CARGO_HTTP_SSL_VERSION=tlsv1.3 CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
  export RUST_LOG=off RUST_BACKTRACE=0
fi
# Python opt's
export PYTHONOPTIMIZE=2 PYTHONIOENCODING='UTF-8' PYTHON_JIT=1
export GOPROXY="direct" # no fancy google cache for go
# ─── Fuzzy finders ─────────────────────────────────────────────────────────
if command -v fd &>/dev/null; then
  FIND_CMD='fd -tf -F --hidden --exclude .git --exclude node_modules --exclude target'
elif command -v rg &>/dev/null; then
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
       FZF_COMPLETION_DIR_OPTS='--info=inline --walker dir,follow' \
       SKIM_DEFAULT_COMMAND="$FIND_CMD" \
       SKIM_DEFAULT_OPTIONS="$FZF_DEFAULT_OPTS"
# ─── Utility Functions ─────────────────────────────────────────────
# which() { command -v "$1" 2>/dev/null || return 1; }
alias which="command -v "

# Having to set a new script as executable always annoys me.
runch() {
  # Args
  local s=$1
  if [ -z "$s" ]; then
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
# ─── Completions ─────────────────────────────────────────────────────────
complete -cf sudo

# Ensure completion directory exists
COMPDIR="$HOME/.config/bash/completions"
mkdir -p "$COMPDIR"
for tool in fzf sk; do
  command -v "$tool" &>/dev/null || continue
  comp="$COMPDIR/${tool}_completion.bash"
  [[ -f $comp ]] || {
    [[ $tool == fzf ]] && "$tool" --bash 2>/dev/null >|"$comp"
    [[ $tool == sk  ]] && "$tool" --shell bash 2>/dev/null >|"$comp"
  }
    . "$comp" 2>/dev/null || {
      [[ $tool == fzf ]] && . <("$tool" --bash 2>/dev/null)
      [[ $tool == sk  ]] && . <("$tool" --shell bash 2>/dev/null)
    }
done; unset tool
# command -v fzf &>/dev/null && eval "$(fzf --bash 2>/dev/null)"
# command -v sk &>/dev/null && . <(sk --shell bash 2>/dev/null)
command -v pay-respects &>/dev/null && eval "$(pay-respects bash 2>/dev/null)"
command -v batman &>/dev/null && eval "$(batman --export-env 2>/dev/null)"
command -v batgrep &>/dev/null && alias batgrep='batgrep --rga -S --color '

if command -v delta &>/dev/null && command -v batdiff &>/dev/null || command -v batdiff.sh &>/dev/null; then
  export BATDIFF_USE_DELTA=true
fi

# Ghostty
if [[ $TERM == xterm-ghostty && -e "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash" ]]; then
    builtin . "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash"
fi

# Wikiman
command -v wikiman &>/dev/null && . /usr/share/wikiman/widgets/widget.bash
# ─── Binds ───────────── ────────────────────────────────────────────
bind 'set completion-query-items 150'
bind 'set page-completions off'
bind 'set show-all-if-ambiguous on'
bind 'set menu-complete-display-prefix on'
bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind "set mark-symlinked-directories on"
bind "set bell-style none"
bind Space:magic-space
bind '"\C-o": kill-whole-line'
# ─── Aliases ─────────────────────────────────────────────────────────
# Enable aliases to be sudo’ed
alias sudo='\sudo '
alias doas='\doas '
alias sudo-rs='\sudo-rs '
alias mkdir='mkdir -p '
alias ed='$EDITOR '
alias smi="sudo -E $(command -v micro)"

alias cls='clear' c='clear'
alias ping='ping -c 4' # Stops ping after 4 requests
alias mount='mount | column -t' # human readable format
alias ptch='patch -p1 <'
alias cleansh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash'
alias updatesh='curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash'

command -v bat &>/dev/null && alias cat='bat -pp '
if command -v eza &>/dev/null; then
  alias ls='eza -al --color=always --group-directories-first --icons' # preferred listing
  alias la='eza -a --color=always --group-directories-first --icons'  # all files and dirs
  alias ll='eza -l --color=always --group-directories-first --icons'  # long format
  alias lt='eza -aT --color=always --group-directories-first --icons' # tree listing
fi
command -v rg &>/dev/null && alias rg='rg --no-stats --color=auto'

if command -v ugrep &>/dev/null; then
  alias grep='ugrep --color=auto'
  alias egrep='ugrep -E --color=auto'
  alias fgrep='ugrep -F --color=auto'
else
  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi
# ─── Jumping ─────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
  export _ZO_FZF_OPTS="--info=inline --tiebreak=index --layout=reverse-list --select-1 --exit-0"
  eval "$(zoxide init bash)"
else
  export ENHANCD_FILTER="$HOME/.cargo/bin/sk:sk:fzf:fzy"
fi
# ─── End ─────────────────────────────────────────────────────────
# Deduplicate PATH (preserve order)
dedupe_path() {
  local dir; local -A seen; local new=()
  for dir in ${PATH//:/ }; do
    [[ -n $dir && -z ${seen[$dir]} ]] && seen[$dir]=1 && new+=("$dir")
  done
  PATH=$(IFS=:; echo "${new[*]}")
}
dedupe_path; export PATH
# force 0 exit-code
true
