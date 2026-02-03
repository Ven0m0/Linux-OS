#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar

EMAIL="${GIT_AUTHOR_EMAIL:-$(git config get user.email)}"
KEY_PATH="$HOME/.ssh/id_git"

if [[ -z "$EMAIL" ]]; then
  echo "Error: git user.email not set. Please set it or export GIT_AUTHOR_EMAIL."
  exit 1
fi

echo "Generating SSH key for $EMAIL..."
mkdir -p ~/.ssh && chmod 700 ~/.ssh

if [[ -f $KEY_PATH ]]; then
  echo "Key $KEY_PATH already exists. Skipping generation."
else
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_PATH" -q -N ""
  echo "Key generated."
fi

# Ensure agent is running
if ! pgrep -u "$USER" ssh-agent >/dev/null; then
  eval "$(ssh-agent -s)"
fi
ssh-add "$KEY_PATH" || true

# Copy to clipboard
if command -v wl-copy >/dev/null; then
  wl-copy <"${KEY_PATH}.pub"
  echo "Public key copied to clipboard (Wayland)."
elif command -v xclip >/dev/null; then
  xclip -sel clipboard <"${KEY_PATH}.pub"
  echo "Public key copied to clipboard (X11)."
else
  echo "Public key:"
  cat "${KEY_PATH}.pub"
fi

echo "Opening GitHub and GitLab settings..."
if command -v xdg-open >/dev/null; then
  xdg-open "https://github.com/settings/keys"
  xdg-open "https://gitlab.com/-/user_settings/ssh_keys"
else
  echo "Open these URLs to add your key:"
  echo "  https://github.com/settings/keys"
  echo "  https://gitlab.com/-/user_settings/ssh_keys"
fi

echo "Scanning known hosts..."
ssh-keyscan -H github.com gitlab.com >>~/.ssh/known_hosts 2>/dev/null || true
sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts

echo "Test GitHub connection..."
ssh -T git@github.com || true

echo "Test GitLab connection..."
ssh -T git@gitlab.com || true
