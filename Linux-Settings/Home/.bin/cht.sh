#!/usr/bin/env bash
set -euo pipefail

# join all arguments with '/', so “topic sub topic” → “topic/sub/topic”
query="${*// /\/}"

# try to fetch the requested cheat‑sheet; on HTTP errors (e.g. 404), fall back to :help
if ! curl -sf "cht.sh/$query"; then
    curl -sf "cht.sh/:help"
fi
