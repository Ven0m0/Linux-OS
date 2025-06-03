#!/bin/bash

URL="$1"
OUTDIR="$2"
OUTFILE="$3"

# Set CURL_BIN to curl-rustls if available, else curl
if command -v curl-rustls &>/dev/null; then
    CURL_BIN="curl-rustls"
else
    CURL_BIN="curl"
fi

# Detect if URL is a sync database file
if [[ "$URL" =~ \.(db|files|sig)(\.xz|\.zst|\.xz\.sig)?$ ]]; then
    # Use selected curl for databases
    "$CURL_BIN" -fL --retry 5 -o "${OUTDIR}/${OUTFILE}" "$URL"
else
    # Use aria2c for packages
    #aria2c -q -x 3 -s 7 -j 7 -R --optimize-concurrent-downloads=true -d "$OUTDIR" -o "$OUTFILE" "$URL"
    aria2c -q -x $(($(nproc) - 1)) -s $(($(nproc) - 1)) -R --optimize-concurrent-downloads=true -d "$OUTDIR" -o "$OUTFILE" "$URL"
fi
