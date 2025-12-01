#!/usr/bin/env bash

# ~/.local/lib/bash_helpers.sh
# Simplified config injection without newline-handling, password-masking,
# backups or DietPi-specific notifications.

G_CONFIG_INJECT() {
  : "${G_PROGRAM_NAME:=G_CONFIG_INJECT}"
  local pattern=${1//\//\\/}
  local setting=$2
  local file=$3
  local after=${4//\//\\/}

  # Ensure writable file
  [[ -w $file ]] || {
    echo "[$G_PROGRAM_NAME] Cannot write to $file" >&2
    return 1
  }

  # Escape setting for regex matching
  local esc="$setting"
  esc=${esc//\\/\\\\}
  esc=${esc//./\\.}
  esc=${esc//+/\\+}
  esc=${esc//\*/\\*}
  esc=${esc//?/\\?}
  esc=${esc//[/\\[}
  esc=${esc//(/\\(}
  esc=${esc//\{/}/\\{} # literal brace
  esc=${esc//^/\\^}
  esc=${esc//&/\\&}
  esc=${esc//\$/\\$}
  esc=${esc//|/\\|}
  esc=${esc//\//\\/}

  # 1) Exact active setting exists?
  if grep -Eq "^[[:blank:]]*$esc\$" "$file"; then
    echo "[$G_PROGRAM_NAME] Already set in $file"
    return 0
  fi

  # 2) Pattern present and unique -> replace first
  if grep -Eq "^[[:blank:]]*$pattern" "$file"; then
    if (($(grep -Ec "^[[:blank:]]*$pattern" "$file") > 1)); then
      echo "[$G_PROGRAM_NAME] Multiple matches for '$pattern' in $file" >&2
      return 1
    fi
    sed -Ei "0,/^[[:blank:]]*$pattern.*\$/s//${setting}/" "$file" || return 1
    echo "[$G_PROGRAM_NAME] Updated setting in $file"
    return 0
  fi

  # 3) Commented-out pattern -> uncomment & replace
  if grep -Eq "^[[:blank:]#;]*$pattern" "$file"; then
    sed -Ei "0,/^[[:blank:]#;]*$pattern.*\$/s//${setting}/" "$file" || return 1
    echo "[$G_PROGRAM_NAME] Uncommented & set in $file"
    return 0
  fi

  # 4) Append after specific line
  if [[ -n $after ]]; then
    if grep -Eq "^[[:blank:]]*$after" "$file"; then
      sed -Ei "0,/^[[:blank:]]*$after.*\$/s//&\\n${setting}/" "$file" || return 1
      echo "[$G_PROGRAM_NAME] Inserted setting after '$after' in $file"
      return 0
    else
      echo "[$G_PROGRAM_NAME] 'After' pattern not found: '$after'" >&2
      return 1
    fi
  fi

  # 5) Fallback: append to end
  [[ -s $file ]] || echo '# Added by bash_helpers' >>"$file"
  sed -Ei "\$a\\${setting}" "$file" || return 1
  echo "[$G_PROGRAM_NAME] Appended setting to end of $file"
}

# Simple, signal-friendly sleep without external command
G_SLEEP_FD=
G_SLEEP() {
  [[ -n $G_SLEEP_FD ]] || exec {G_SLEEP_FD}<> <(:)
  read -rt "$1" -u "$G_SLEEP_FD" || :
}
