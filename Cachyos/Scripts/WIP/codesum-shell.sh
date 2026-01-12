#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

has(){ command -v -- "$1" &>/dev/null; }
msg(){ printf '%s\n' "$@"; }
log(){ printf '%s\n' "$@" >&2; }
die(){ printf '%s\n' "$1" >&2; exit "${2:-1}"; }
# Constants
readonly SUMMARY_DIR=".summary_files"
readonly IGNORE_LIST=(". git" "venv" "__pycache__" ".vscode" ".idea" "node_modules" "build" "dist" "*.pyc" "*. pyo" "*.egg-info" ".DS_Store" ".env" "$SUMMARY_DIR")
readonly OUTPUT_FILE="${SUMMARY_DIR}/code_summary.md"
has python3 || die "python3 not found.  Install Python 3.8+." 2
# Detect repo root or use current directory
detect_root(){
  local d="${1:-.}"
  while [[ "$d" != "/" ]]; do
    [[ -d "$d/. git" ]] && { printf '%s' "$d"; return; }
    d=$(cd "$d/.." && pwd)
  done
  pwd
}
ROOT=$(detect_root .)
cd "$ROOT" || die "Cannot cd to $ROOT" 1
mkdir -p "$SUMMARY_DIR"
# Build ignore patterns from . gitignore + defaults
build_ignore_pattern(){
  local pats=()
  for p in "${IGNORE_LIST[@]}"; do
    pats+=(-not -path "*/$p/*" -not -name "$p")
  done
  [[ -f .gitignore ]] && while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    pats+=(-not -path "*/${line}/*" -not -name "$line")
  done <. gitignore
  printf '%s\n' "${pats[@]}"
}
# Collect text files
collect_files(){
  local -a pats; mapfile -t pats < <(build_ignore_pattern)
  find . -type f "${pats[@]}" -exec file --mime-type {} + \
    | awk -F:  '/text\//||/json/||/xml/||/yaml/||/toml/{print $1}' \
    | sed 's|^\./||'
}
# Generate summary with Python
generate_summary(){
  python3 - "$@" <<'PYEOF'
import sys, json, hashlib, re, os
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError
# Rough token estimator (4 chars ≈ 1 token for English code)
def estimate_tokens(text:  str)->int:  return len(text)//4
def is_binary(path: Path)->bool:
  try:
    with path.open('rb') as f: chunk=f.read(8192)
    return b'\x00' in chunk
  except:  return True
def parse_tree_sitter(code: str, lang: str)->dict:
  """Stub:  Tree-sitter parsing for semantic compression."""
  lines=code.split('\n')
  funcs=[]
  for i,l in enumerate(lines,1):
    if re.search(r'\bdef\s+\w+|\bfunction\s+\w+|\bclass\s+\w+',l):
      funcs.append({'line':i,'text':l. strip()})
  return {'functions':funcs,'lines':len(lines)}
def compress_code(code: str, lang: str)->str:
  """Semantic compression:  extract signatures, remove comments."""
  meta=parse_tree_sitter(code,lang)
  sigs='\n'.join(f"L{f['line']}: {f['text']}" for f in meta['functions'][: 50])
  return f"# {meta['lines']} lines\n{sigs}\n# [truncated]"
def summarize_files(files: list, compress: bool=False):
  root=Path('.')
  summary_parts=["# Code Summary\n"]
  total_tokens=0
  for fpath in files:
    p=Path(fpath)
    if not p.exists() or is_binary(p): continue
    try:
      content=p.read_text(encoding='utf-8',errors='ignore')
      lang=p.suffix.lstrip('.')
      if compress and len(content)>5000:
        content=compress_code(content,lang)
      tokens=estimate_tokens(content)
      total_tokens+=tokens
      summary_parts.append(f"\n## File: {fpath}\n```{lang}\n{content}\n```\n")
    except Exception as e:
      summary_parts.append(f"\n## File: {fpath}\n*Error: {e}*\n")
  summary_parts.append(f"\n---\n**Estimated tokens**:  ~{total_tokens}\n")
  return ''.join(summary_parts)
def main():
  compress='--compress' in sys.argv
  files=sys.stdin.read().strip().split('\n')
  summary=summarize_files([f for f in files if f],compress=compress)
  print(summary)
if __name__=='__main__':  main()
PYEOF
}
# Interactive file selection (simple y/n prompt)
select_files_interactive(){
  local -a files; mapfile -t files < <(collect_files)
  local -a selected=()
  log "Found ${#files[@]} text files.  Select files to summarize (y/n/a=all/q=quit):"
  for f in "${files[@]}"; do
    printf '%s?  ' "$f" >&2
    read -r answer
    case "$answer" in
      y|Y) selected+=("$f");;
      a|A) selected=("${files[@]}"); break;;
      q|Q) break;;
    esac
  done
  printf '%s\n' "${selected[@]}"
}
# Main flow
main(){
  local compress=false all=false
  while (($#)); do
    case "$1" in
      --compress|-c) compress=true;;
      --all|-a) all=true;;
      --help|-h) msg "Usage: $0 [--compress] [--all] [--help]"; msg "  --compress  Semantic compression for large files"; msg "  --all       Auto-select all files"; exit 0;;
      *) die "Unknown option: $1" 1;;
    esac; shift
  done
  log "Scanning $ROOT for code files..."
  local -a files
  if $all; then
    mapfile -t files < <(collect_files)
  else
    mapfile -t files < <(select_files_interactive)
  fi
  [[ ${#files[@]} -eq 0 ]] && die "No files selected." 0
  log "Generating summary for ${#files[@]} files..."
  printf '%s\n' "${files[@]}" | {
    if $compress; then
      generate_summary --compress >"$OUTPUT_FILE"
    else
      generate_summary >"$OUTPUT_FILE"
    fi
  }
  msg "✓ Summary written to $OUTPUT_FILE"
  local tokens; tokens=$(grep -oP '(?<=tokens\*\*:  ~)\d+' "$OUTPUT_FILE" || echo "? ")
  msg "  Estimated tokens: ~$tokens"
  [[ -f "$OUTPUT_FILE" ]] && { has xclip && xclip -sel clip <"$OUTPUT_FILE" && msg "  Copied to clipboard (xclip)"; true; }
}
main "$@"
