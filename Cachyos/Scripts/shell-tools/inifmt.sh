#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar; LC_ALL=C
# inifmt: Compact INI formatter
# Usage: inifmt [file] (reads stdin if no file)
inifmt(){
  awk 'function t(s){gsub(/^[ \t]+|[ \t]+$/,"",s);return s}
    /^[ \t]*([;#]|$)/ {print; next}
    /^[ \t]*\[/       {print t($0); next}
    match($0,/=/)     {print t(substr($0,1,RSTART-1)) " = " t(substr($0,RSTART+1)); next}
  ' "${1:-/dev/stdin}"
}
inifmt
