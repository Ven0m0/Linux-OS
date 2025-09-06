#!/usr/bin/env bash

nekofetch(){
  local CAT="${1:-}" JT="${2:-}" IT="${3:-}"
  if [[ -n "$JT" ]] && command -v "$JT" &>/dev/null; then
    JSONT="$JT"
  elif command -v jaq &>/dev/null; then
    JSONT=jaq
  elif command -v jq &>/dev/null; then
    JSONT=jq
  fi
  if [[ -n $IMGT ]] && command -v "$IMGT" &>/dev/null; then
    IMGT="$IT"
  elif command -v chafa &>/dev/null; then
    IMGT=chafa
  fi
  if [[ -z $CAT ]]; then
  IMG_URL="$(curl -s "https://nekos.best/api/v2/${CAT}" | "$JSONT" -r '.results[0].url')"
  curl -s "$IMG_URL" | "$IMGT" -O 6 -w 4 --clear
  printf '%s\n' "Usage: nekofetch <category> <json-tool>"
  printf '%s\n' "  categories: husbando, kitsune, neko, waifu"
  printf '%s\n' "  JSON tools: jaq, jq"
}
