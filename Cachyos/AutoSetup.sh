#!/bin/bash

sudo -v

# Determine the device mounted at root
ROOT_DEV=$(findmnt -n -o SOURCE /)

# Check the filesystem type of the root device
FSTYPE=$(findmnt -n -o FSTYPE /)

# If the filesystem is ext4, execute the tune2fs command
if [[ "$FSTYPE" == "ext4" ]]; then
    echo "Root filesystem is ext4 on $ROOT_DEV"
    sudo tune2fs -O fast_commit "$ROOT_DEV"
else
    echo "Root filesystem is not ext4 (detected: $FSTYPE). Skipping tune2fs."
fi

balooctl6 disable
xprop -remove _KDE_NET_WM_SHADOW
