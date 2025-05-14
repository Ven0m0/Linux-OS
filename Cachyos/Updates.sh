#!/usr/bin/env bash

sudo pacman -Syu --noconfirm
sudo topgrade -c --disable config_update --skip-notify -y
