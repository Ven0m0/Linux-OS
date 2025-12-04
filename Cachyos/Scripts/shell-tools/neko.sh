#!/usr/bin/env bash
export LC_ALL=C LANG=C

nekofetch() {
  local cat="${1:-}" json_tool="${2:-}" img_tool="${3:-}"
  local jsont imgt api_base="https://nekos.best/api/v2"
  local response img_url tmp_file
  # 1. Select JSON Parser (prefer user arg > jaq > jq)
  if [[ -n $json_tool ]] && command -v "$json_tool" &>/dev/null; then
    jsont="$json_tool"
  elif command -v jaq &>/dev/null; then
    jsont="jaq"
  elif command -v jq &>/dev/null; then
    jsont="jq"
  else
    printf 'error: no json tool found (install jaq or jq)\n' >&2; return 1
  fi
  # 2. Select Image Renderer (prefer user arg > chafa > cat)
  if [[ -n $img_tool ]] && command -v "$img_tool" &>/dev/null; then
    imgt="$img_tool"
  elif command -v chafa &>/dev/null; then
    imgt="chafa"
  else
    imgt="cat"
  fi
  # 3. List Categories (if none provided)
  if [[ -z $cat ]]; then
    printf 'Usage: nekofetch <category> [json-tool] [img-tool]\n\n'
    # Only fetch endpoints here
    response="$(curl -fsSL "$api_base/endpoints")" || { printf 'error: failed to fetch endpoints\n' >&2; return 2; }
    printf 'Available categories:\n'
    # Pretty print with column if available
    if command -v column &>/dev/null; then
      printf '%s' "$response" | "$jsont" -r 'to_entries[] | "\(.key)\t\(.value.format)"' | column -t -s $'\t'
    else
      printf '%s' "$response" | "$jsont" -r 'keys[]'
    fi; return 0
  fi
  # 4. Fetch Image Metadata
  # Optimistic fetch: directly hit the category endpoint. Fails fast if invalid.
  response="$(curl -fsSL "$api_base/$cat")" || { printf 'error: failed to fetch data (check category "%s")\n' "$cat" >&2; return 3; }
  img_url="$(printf '%s' "$response" | "$jsont" -r '.results[0].url')"
  [[ -n $img_url && $img_url != "null" ]] || { printf 'error: failed to extract image URL\n' >&2; return 4; }
  # 5. Render or Download
  if [[ $imgt == "chafa" ]]; then
    # Optimization: Stream directly to stdout -> chafa (no disk I/O)
    curl -fsSL "$img_url" | chafa -O 9 -w 9 --clear -
  else
    # Fallback: Download to temp file
    tmp_file="$(mktemp "/tmp/neko_${cat}.XXXXXX")" || return 5
    # Ensure cleanup on return, unless we are just printing the path
    trap 'rm -f "$tmp_file"' RETURN
    if curl -fsSL "$img_url" -o "$tmp_file"; then
      if [[ $imgt == "cat" ]]; then
        printf 'Image saved to: %s\n' "$tmp_file"
        trap - RETURN # Keep file if user just wanted to download
      else
        "$imgt" "$tmp_file"
      fi
    else
      printf 'error: download failed\n' >&2; return 6
    fi
  fi
}
