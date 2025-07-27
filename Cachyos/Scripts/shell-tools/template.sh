#!/usr/bin/env bash
# shellcheck shell=bash
set -eECuo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
# shopt -s extglob
LC_COLLATE=C LC_CTYPE=C.UTF-8 LANG=C.UTF-8

sudo -v

