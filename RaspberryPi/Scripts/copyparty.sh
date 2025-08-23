#!/usr/bin/env bash
LC_ALL=C LANG=C

# UID/GID >= 100 (or <1000 for system account)
uid=200
gid=200

# Create group
echo "copyparty:x:$gid:" >> /etc/group

# Create user
echo "copyparty:x:$uid:$gid:Copyparty user:/var/lib/copyparty:/sbin/nologin" >> /etc/passwd
echo "copyparty:!::0:99999:7:::" >> /etc/shadow

# Create home dir
mkdir -p /var/lib/copyparty
chown $uid:$gid /var/lib/copyparty
