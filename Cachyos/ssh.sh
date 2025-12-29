#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar

EMAIL="${GIT_AUTHOR_EMAIL:-$(git config get user.email)}"

mkdir -p ~/.ssh && chmod -R 700 ~/.ssh
ssh-keygen -t ed25519 -C "$EMAIL" -f ~/.ssh/id_git -q
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_git

wl-copy -r < ~/.ssh/id_git.pub || xclip -sel clipboard < ~/.ssh/id_git.pub
xdg-open
echo "copy to to https://github.com/settings/keys and https://gitlab.com/-/user_settings/ssh_keys"

ssh-keyscan -H github.com gitlab.com >>~/.ssh/known_hosts

echo "Test GitHub connection"
ssh -T git@github.com
echo "Test GitLab connection"
ssh -T git@gitlab.com
