#!/usr/bin/env bash
# shellcheck shell=bash
set -eECuo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
# shopt -s extglob
LC_COLLATE=C LC_CTYPE=C.UTF-8 LANG=C.UTF-8

sudo -v

this_script_dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

echo $this_script_dir
cd $this_script_dir
