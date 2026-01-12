#!/usr/bin/env python3
"""Claude Code MCP tool: Optimized code context generation."""
import sys
import json
from pathlib import Path

# Import the codesum module
sys.path.insert(0, str(Path(__file__).parent))
from codesum import Config, collect_files, create_summary, parse_gitignore, SUMMARY_DIR

def generate_context(project_dir: str = ".") -> dict:
  """Generate optimized code context for Claude Code."""
  root = Path(project_dir).resolve()
  if not root.exists():
    return {"error": f"Directory not found: {root}"}
  
  summary_dir = root / SUMMARY_DIR
  summary_dir.mkdir(exist_ok=True)
  
  cfg = Config(
    root=root,
    summary_dir=summary_dir,
    compress=False,  # Fast mode for interactive use
    ignore_patterns=parse_gitignore(root)
  )
  
  # Collect all files
  entries = list(collect_files(cfg))
  if not entries:
    return {"error": "No text files found"}
  
  # Auto-select all for non-interactive use
  summary = create_summary(cfg, entries)
  
  # Write output
  output = summary_dir / "code_summary.md"
  output.write_text(summary)
  
  total_tokens = sum(e.tokens for e in entries)
  
  return {
    "summary": summary,
    "file_count": len(entries),
    "token_count": total_tokens,
    "output_path": str(output)
  }

def main():
  """MCP-style tool invocation."""
  if len(sys.argv) > 1:
    project_dir = sys.argv[1]
  else:
    project_dir = "."
  
  result = generate_context(project_dir)
  
  if "error" in result:
    print(json.dumps({"error": result["error"]}), file=sys.stderr)
    return 1
  
  # Output summary directly for Claude Code to consume
  print(result["summary"])
  
  # Log stats to stderr
  print(f"✓ Files: {result['file_count']} | Tokens: ~{result['token_count']:,}", file=sys.stderr)
  
  return 0

if __name__ == "__main__":
  sys.exit(main())
