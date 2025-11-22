#!/usr/bin/env bash
export LC_ALL=C LANG=C

nekofetch() {
  local CAT="${1:-}" JT="${2:-}" IT="${3:-}"
  local JSONT IMGT endpoints formats img_url fmt tmpfile
  # pick json tool
  if [[ -n $JT ]] && command -v "$JT" &> /dev/null; then
    JSONT="$JT"
  elif command -v jaq &> /dev/null; then
    JSONT=jaq
  elif command -v jq &> /dev/null; then
    JSONT=jq
  else
    printf 'error: no json tool found (jaq or jq required)\n' >&2
    return 1
  fi
  # pick image tool
  if [[ -n $IT ]] && command -v "$IT" &> /dev/null; then
    IMGT="$IT"
  elif command -v chafa &> /dev/null; then
    IMGT=chafa
  else
    IMGT=cat
  fi
  # fetch endpoints
  endpoints="$(curl -s 'https://nekos.best/api/v2/endpoints')" || {
    printf 'error: failed to fetch endpoints\n' >&2
    return 2
  }
  # build "category<TAB>format" lines using chosen json tool
  if [[ $JSONT == "jaq" ]]; then
    formats="$(printf '%s' "$endpoints" | jaq -r 'to_entries[] | "\(.key)\t\(.value.format)"')"
  else
    formats="$(printf '%s' "$endpoints" | jq -r 'to_entries[] | "\(.key)\t\(.value.format)"')"
  fi
  # no category => show usage + available categories
  if [[ -z $CAT ]]; then
    printf 'Usage: nekofetch <category> [json-tool] [img-tool]\n'
    printf 'Available categories (category<TAB>format):\n'
    printf '%s\n' "$formats"
    return 0
  fi
  # check category exists and get format
  fmt="$(printf '%s\n' "$formats" | awk -F'\t' -v c="$CAT" '$1==c{print $2; exit}')"
  if [[ -z $fmt ]]; then
    printf 'error: unknown category: %s\n' "$CAT" >&2
    return 3
  fi
  # fetch image URL from API
  if [[ $JSONT == "jaq" ]]; then
    img_url="$(curl -s "https://nekos.best/api/v2/${CAT}" | jaq -r '.results[0].url')"
  else
    img_url="$(curl -s "https://nekos.best/api/v2/${CAT}" | jq -r '.results[0].url')"
  fi
  [[ -n $img_url ]] || {
    printf 'error: failed to obtain image URL\n' >&2
    return 4
  }
  # display or save+open depending on renderer
  if [[ $IMGT == "chafa" ]]; then
    curl -s "$img_url" | chafa -O 6 -w 4 --clear
  else
    tmpfile="$(mktemp /tmp/nekofetch.XXXXXX)" || {
      printf 'error: mktemp failed\n' >&2
      return 5
    }
    trap 'rm -f "$tmpfile"' EXIT
    curl -s "$img_url" > "$tmpfile"
    # try to run renderer, else fall back to printing path
    if command -v "$IMGT" &> /dev/null; then
      "$IMGT" "$tmpfile"
    else
      printf 'image saved to: %s\n' "$tmpfile"
    fi
    trap - EXIT
  fi
}
