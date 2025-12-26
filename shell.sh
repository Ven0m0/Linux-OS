#!/usr/bin/env bash

# TODO: find a use for these and compact them
NanoPager(){
  local file="$1" progname=${0##*/}
  local -r nano=/bin/nano
  if [ -x $nano ] ; then
    local cmd="$nano +1 --modernbindings --view"
    if [ "$file" ] ; then
      if [ -e "$file" ] ; then
        $cmd "$file"
      else
        echo "==> $progname: file $file not found" >&2
      fi
    else
      $cmd -
    fi
  else
   echo "==> $progname: 'nano' is not installed" >&2; return 1
  fi
}

ProgressBar(){         # This function was converted from the work of @Kresimir, thanks!
  local msg="$1" percent="$2" barlen="$3" c columns="$COLUMNS" 
  [[ -n "$columns" ]] || columns=80                         # guess nr of columns on the terminal
  local msglen=$((columns - barlen - 9))                  # max space for the msg
  [[ "${#msg}" -gt "$msglen" ]] && msg="${msg::$msglen}"    # msg must be truncated
  [ "${msg: -1}" = ":" ]] || msg+=":"                      # make sure a colon is after msg
  printf "\r%-*s %3d%% [" "$msglen" "$msg" "$percent" >&2
  for ((c = 0; c < barlen; c++)) ; do
    if (( c <= percent * barlen / 100 )); then
      echo -ne "#" >&2
    else
      echo -ne " " >&2
    fi
  done; stdbuf -oL printf "]" >&2 # flush stdout
}
ProgressBarInit(){ trap 'printf "\x1B[?25h" >&2' EXIT; printf "\x1B[?25l" >&2; }
ProgressBarEnd(){ printf "\n" >&2; }


git config --global --add safe.directory "$GITHUB_WORKSPACE"
git config --global --add safe.directory "$PWD"


duperemove -r -d "/run/media/lucy/storage"
beesd "/run/media/lucy/storage"


adb shell pm compile -a --full -r cmdline -p PRIORITY_INTERACTIVE_FAST --force-merge-profile -m speed-profile
pm compile -a --full -r cmdline -p PRIORITY_INTERACTIVE_FAST --force-merge-profile -m speed-profile
adb shell pm compile -m verify -f -a

