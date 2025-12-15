#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
[[ $- != *i* ]] && return
# --- Keybindings ---
# These work universally as they are mksh/terminal features
set -o emacs
bind '"\e[1;5D"=backward-word'    # Ctrl+Left
bind '"\e[1;5C"=forward-word'     # Ctrl+Right
bind '"\e[A"=search-history-up'   # Up arrow history search
bind '"\e[B"=search-history-down' # Down arrow history search
bind ^[a=beginning-of-line
bind ^[e=end-of-line
export HISTCONTROL="ignoredups:ignorespace"
# Report status of background jobs immediately upon completion
set -o notify
# Run background jobs at a lower priority (also disables the bell)
set -o bgnice
# Prevent accidental overwrites when redirecting output with>
# Use>| to force an overwrite.
set -o noclobber
# Function to create a directory and move into it
set +o nohup # disable nohup mode
set -o utf8-mode
mkcd() {
  mkdir -p "$1" && cd "$1" || exit
}
cdl() {
  cd "$1" && ls -a --color=auto
}
export CDPATH=".:~:/sdcard:/sdcard/Android/data:/:/storage/emulated/0"
# File patterns to ignore during tab completion
export FIGNORE='.o:~:*.swp'
alias grep='grep --color=auto'
# Package Manager (pm)
alias pml='pm list packages'
alias pml3='pm list packages -3' # 3rd party only
alias pmp='pm path'
alias pmd='pm dump'

# Logcat
alias lc='logcat -v brief'
alias lct='logcat -v threadtime'
alias lce='logcat *:E' # Errors only

# Some usefull aliases
alias ls="ls --color=auto -FA"
alias l="ls --color=auto -Fl"
alias ll="ls --color=auto -FAl"
alias la="ls --color=auto -Fa"

alias cls=clear

alias ..="cd ../"
alias ....="cd ../../"
alias ......="cd ../../../"
alias ........="cd ../../../../"

# Show current focused app and activity
current_activity() {
  dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp'
}

# a function to help users find the local ip (from gh:omz/sysadmin plugin)
myip() {
  if [[ -x "$(command -v 'ip')" ]]; then
    ip addr | awk '/inet /{print $2}' | grep -v 127.0.0.1
  else
    ifconfig | awk '/inet /{print $2}' | grep -v 127.0.0.1
  fi
}

# Simulate 'man' command using --help output
man() {
  [[ -z $1 ]] && {
    echo -e "What manual page do you want?\nFor example, try 'man ls'." >&2
    return 1
  }
  "$1" --help &> /dev/null && "$1" --help 2>&1 || {
    echo "No manual entry for $1" >&2
    return 16
  }
}

# --- 1. Define Colors ---
MGN=$'\e[35m'
BLU=$'\e[34m'
YLW=$'\e[33m'
BLD=$'\e[1m'
UND=$'\e[4m'
GRN=$'\e[32m'
CYN=$'\e[36m'
DEF=$'\e[0m'
RED=$'\e[31m'
PNK=$'\e[38;5;205m'

# --- 2. Set the PS1 evaluation string ---
PS1='
  local ret=$?
  # --- User ---
  local USERN="${MGN}$USER${DEF}"
  (( EUID == 0 )) && USERN="${RED}$USER${DEF}"
  # --- Hostname ---
  local HOSTL="${BLU}${HOSTNAME:-$(hostname -s)}${DEF}"
  # Check for an SSH connection (this also works for sshd on-device).
  [[ -n $SSH_CONNECTION ]] && HOSTL="${YLW}${HOSTNAME:-$(hostname -s)}${DEF}"
  # --- Working Directory ---
  local WDIR="${CYN}${PWD/#$HOME/~}${DEF}"
  # --- Time ---
  # %H:%M gives the 24-hour time
  local TIME="${PNK}$(date +%H:%M)${DEF}"
  # --- Exit Status Indicator ---
  local EXSTAT
  if (( ret == 0 )); then
    EXSTAT="${GRN}:)${DEF}"
  else
    EXSTAT="${RED}D:${DEF}"
  fi
  # --- Prompt Character ---
  # Sets "#" for root, "$" for normal users
  local PCHAR="$"
  (( EUID == 0 )) && PCHAR="#"
  local BOLD_PCHAR="${BLD}${PCHAR}${DEF}"
  # --- Final Assembly ---
  # Assembles the prompt string
  print -n "[${USERN}@${HOSTL}${UND}|${DEF}${WDIR}]>${TIME}|${EXSTAT} ${BOLD_PCHAR} "
'
PS2='> '
# Keep PS4 with timestamps
PS4='[$EPOCHREALTIME] '
