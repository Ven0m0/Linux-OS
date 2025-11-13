#!/usr/bin/env bash
# shellcheck shell=bash

# Setup environment
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'

net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
