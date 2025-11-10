#!/usr/bin/env bash

if [[ -f "/etc/default/dropbear" ]]; then
  sed -i 's/NO_START\=1/NO_START\=0/g' /etc/default/dropbear
fi
if [[ -f "/etc/ssh/sshd_config" ]]; then
  sed -i 's/#PermitRootLogin prohibit\-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
  sed -i 's/PermitRootLogin without\-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
  sed -i 's/#PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config
  sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
fi
