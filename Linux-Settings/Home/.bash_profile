#
# ~/.bash_profile
#

[[ -f $HOME/.bashrc ]] && . "$HOME/.bashrc
[[ -f ~/.profile ]] && . "$HOME/.profile"
[[ -f $HOME/.cargo/env ]] && . "$HOME/.cargo/env"

_prependpath() {
    # Only prepend if not already in PATH
    [[ -d $1 ]] && [[ ":$PATH:" != *":$1:"* ]] && PATH="$1${PATH:+:$PATH}"
}
_prependpath "$HOME/.local/bin"
_prependpath "$HOME/bin"
export PATH
