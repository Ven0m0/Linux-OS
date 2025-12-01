#!/usr/bin/env bash
# --- autoload dirs ---
func_dirs="$HOME/.bash/functions.d" # lazy function scripts
config_dirs="$HOME/.bash/configs"   # normal config scripts
autoload_cache="$HOME/.cache/bash_autoload.list"
config_cache="$HOME/.cache/bash_config.loaded"

lazyfile(){
  local src=$1
  shift
  for f; do
    eval "$f(){ unset -f $*; source \"$src\"; $f \"\$@\"; }"
  done
}

autoload_parse(){
  local src=$1 funcs
  if command -v rg &>/dev/null; then
    funcs=$(rg -n --no-heading '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)' "$src")
  else
    funcs=$(grep -Eo '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)' "$src")
  fi

  if command -v sd &>/dev/null; then
    funcs=$(printf '%s\n' "$funcs" | sd '^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\).*' '$1')
  else
    funcs=$(printf '%s\n' "$funcs" | sed -E 's/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\).*/\1/')
  fi
  printf '%s\n' "$funcs"
}

autoload_init(){
  local cache_valid=1 config_valid=1

  # check function cache
  [[ -f $autoload_cache ]] || cache_valid=0
  if [[ $cache_valid -eq 1 ]]; then
    for src in "$func_dirs"/*.sh; do
      [[ $src -nt $autoload_cache ]] && {
        cache_valid=0
        break
      }
    done
  fi

  # check config cache
  [[ -f $config_cache ]] || config_valid=0
  if [[ $config_valid -eq 1 ]]; then
    for src in "$config_dirs"/*.sh; do
      [[ $src -nt $config_cache ]] && {
        config_valid=0
        break
      }
    done
  fi

  # regenerate function cache
  if [[ $cache_valid -eq 0 ]]; then
    : > "$autoload_cache"
    shopt -s nullglob
    for src in "$func_dirs"/*.sh; do
      autoload_parse "$src" | while read -r fn; do
        echo "$fn $src" >> "$autoload_cache"
      done
    done
    shopt -u nullglob
  fi

  # load stubs for functions
  while read -r fn src; do
    [[ $src == "$func_dirs"* ]] && lazyfile "$src" "$fn"
  done < "$autoload_cache"

  # regenerate config cache and source configs
  if [[ $config_valid -eq 0 ]]; then
    : > "$config_cache"
    shopt -s nullglob
    for src in "$config_dirs"/*.sh; do
      source "$src"
      echo "$src" >> "$config_cache"
    done
    shopt -u nullglob
  else
    # just source cached configs
    shopt -s nullglob
    while read -r src; do
      [[ -f $src ]] && source "$src"
    done < "$config_cache"
    shopt -u nullglob
  fi
}

# --- helpers ---
autoload_list(){ awk '{print $1}' "$autoload_cache" 2>/dev/null | sort -u; }
autoload_show(){ awk -v f="$1" '$1==f {print $2}' "$autoload_cache" 2>/dev/null; }

autoload_init
unset -f autoload_init autoload_parse lazyfile
