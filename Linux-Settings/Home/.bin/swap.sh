#!/bin/bash

# swaps two files
# part of shell-tools (GPLv3)

if [ $# -ne 2 ]; then
    echo "Usage: swap file1 file2"
    echo "Supports copying into ram"
fi

TMPFILE=""
if [ -d "$1" ]; then
    echo "$1 is a directory"
    TMPFILE=tmp.$$
    #TMPFILE=$(mktemp -d)
else
    TMPFILE=$(mktemp)
fi
# && runs only if the preceding was successful
mv "$1" $TMPFILE && mv "$2" "$1" && mv $TMPFILE "$2"
