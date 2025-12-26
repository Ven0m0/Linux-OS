#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

# Git safe directory configuration for CI/CD and local environments
git config --global --add safe.directory "${GITHUB_WORKSPACE:-$PWD}"
git config --global --add safe.directory "$PWD"
