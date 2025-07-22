#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
set -CE
IFS=$'\n\t'
shopt -s nullglob globstar
# shopt -s extglob

sudo -v

LC_COLLATE=C
LC_CTYPE=C.UTF-8
