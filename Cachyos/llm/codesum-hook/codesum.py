#!/usr/bin/env python3
"""
Optimized Code Summarizer & MCP Tool.
Modes: CLI (default), MCP (--mcp), Hook (--hook).
Deps: None (Optional: openai, tiktoken).
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, List, Optional, Set, Pattern, Any, Dict

# --- Optional Imports ---
try:
    import tiktoken
    HAS_TIKTOKEN = True
except ImportError:
    HAS_TIKTOKEN = False

try:
    from openai import OpenAI
    HAS_OPENAI = True
except ImportError:
    HAS_OPENAI = False

# --- Constants ---
SUMMARY_DIR = ".summary_files"
OUTPUT_FILE = "code_summary.md"
CACHE_FILE = "cache.json"

# Base ignores - highly optimized list
DEFAULT_IGNORES = [
    ".git", ".svn", ".hg", "venv", ".venv", "env", "__pycache__",
    ".vscode", ".idea", ".ds_store", "node_modules", "bower_components",
    "build", "dist", "target", "out", "coverage", ".tox",
    "*.pyc", "*.pyo", "*.pyd", "*.so", "*.dll", "*.exe", "*.bin",
    "*.egg-info", "*.lock", "package-lock.json", "yarn.lock",
    SUMMARY_DIR
]

# Fast extension checks
BINARY_EXTS = {
    '.png', '.jpg', '.jpeg', '.gif', '.ico', '.webp', '.svg',
    '.mp3', '.mp4', '.wav', '.avi', '.mov', '.mkv',
    '.zip', '.tar', '.gz', '.7z', '.rar', '.pdf',
    '.db', '.sqlite', '.parquet', '.pkl'
}

@dataclass(slots=True)
class FileEntry:
    path: Path
    rel_path: str
    size: int
    tokens: int = 0

@dataclass
class Config:
    root: Path
    summary_dir: Path
    mode: str = "cli"  # cli, mcp, hook
    compress: bool = False
    api_key: Optional[str] = None
    model: str = "gpt-4o-mini"
    ignore_patterns: List[str] = field(default_factory=list)
    _compiled_ignores: List[Pattern] = field(default_factory=list, init=False)

    def __post_init__(self):
        # Compile globs to regex for speed
        combined = DEFAULT_IGNORES + self.ignore_patterns
        self._compiled_ignores = [
            re.compile(fnmatch.translate(p)) for p in combined
        ]

# --- Core Logic ---

def is_binary(path: Path) -> bool:
    """Fast binary check: Extension -> Null Byte Sniff."""
    if path.suffix.lower() in BINARY_EXTS:
        return True
    try:
        with path.open('rb') as f:
            chunk = f.read(1024)
            return b'\x00' in chunk
    except OSError:
        return True

def parse_gitignore(root: Path) -> List[str]:
    """Read .gitignore and return patterns."""
    patterns = []
    ignore_file = root / ".gitignore"
    if ignore_file.is_file():
        try:
            content = ignore_file.read_text(encoding='utf-8')
            for line in content.splitlines():
                line = line.strip()
                if line and not line.startswith('#'):
                    # Strip leading slash for easier matching
                    patterns.append(line.lstrip('/'))
        except OSError:
            pass
    return patterns

def should_ignore(rel_path: str, cfg: Config) -> bool:
    """Check if path matches any compiled regex."""
    # Normalize path separator
    name = os.path.basename(rel_path)
    # Fast check for hidden files/dirs (except .gitignore/config)
    if name.startswith('.') and name not in {'.gitignore', '.env'}:
         # Allow some specific hidden configs if needed, but generally ignore hidden
         pass 
    
    for pattern in cfg._compiled_ignores:
        if pattern.match(rel_path) or pattern.match(name):
            return True
    return False

def collect_files(cfg: Config) -> Iterator[FileEntry]:
    """Optimized file walker using os.scandir."""
    root_str = str(cfg.root)
    
    # Walk top-down
    for root, dirs, files in os.walk(root_str, topdown=True):
        rel_root = os.path.relpath(root, root_str)
        if rel_root == ".":
            rel_root = ""
        
        # Prune dirs in-place
        dirs[:] = [
            d for d in dirs 
            if not should_ignore(os.path.join(rel_root, d), cfg)
        ]
        
        for name in files:
            rel_path = os.path.join(rel_root, name) if rel_root else name
            if should_ignore(rel_path, cfg):
                continue
            
            full_path = Path(root) / name
            if is_binary(full_path):
                continue

            try:
                stat = full_path.stat()
                if stat.st_size > 1_000_000: # Skip > 1MB text files
                    continue
                yield FileEntry(path=full_path, rel_path=rel_path, size=stat.st_size)
            except OSError:
                continue

def count_tokens(text: str) -> int:
    """Accurate or estimated token count."""
    if HAS_TIKTOKEN:
        try:
            enc = tiktoken.get_encoding("o200k_base")
            return len(enc.encode(text))
        except Exception:
            pass
    return len(text) // 4

def compress_content(cfg: Config, text: str, context: str) -> str:
    """AI compression wrapper."""
    if not (HAS_OPENAI and cfg.api_key and cfg.compress):
        return text
    
    try:
        client = OpenAI(api_key=cfg.api_key)
        resp = client.chat.completions.create(
            model=cfg.model,
            messages=[
                {"role": "system", "content": "Minify code. Keep signatures/logic. Remove comments/whitespace."},
                {"role": "user", "content": f"File: {context}\n\n{text}"}
            ],
            max_tokens=2000,
            temperature=0
        )
        return resp.choices[0].message.content or text
    except Exception as e:
        sys.stderr.write(f"Compress err ({context}): {e}\n")
        return text

def generate_tree(files: List[FileEntry]) -> str:
    """Generate visual tree structure."""
    lines = []
    seen = set()
    for f in sorted(files, key=lambda x: x.rel_path):
        parts = f.rel_path.split(os.sep)
        for i in range(len(parts)):
            path = os.sep.join(parts[:i+1])
            if path in seen: 
                continue
            seen.add(path)
            indent = "  " * i
            marker = "├── " if i < len(parts) -1 else "├── "
            # Simple tree logic for flatness
            lines.append(f"{indent}{marker}{parts[i]}")
    return "\n".join(lines[:200]) # Cap tree size

def generate_summary(cfg: Config) -> Dict[str, Any]:
    """Orchestrate scanning and summary generation."""
    entries = list(collect_files(cfg))
    if not entries:
        return {"error": "No matching text files found."}

    # Load cache
    cache_path = cfg.summary_dir / CACHE_FILE
    cache = {}
    if cfg.compress and cache_path.exists():
        try:
            cache = json.loads(cache_path.read_text())
        except Exception:
            pass

    output_lines = [
        f"# Project Summary: {cfg.root.name}",
        f"Files: {len(entries)} | Mode: {'Compressed' if cfg.compress else 'Raw'}",
        "\n## Structure",
        "```text",
        generate_tree(entries),
        "```",
        "\n---"
    ]

    total_tokens = 0
    new_cache = {}

    for entry in entries:
        try:
            content = entry.path.read_text(encoding='utf-8', errors='ignore')
            
            # Compression / Caching logic
            final_content = content
            if cfg.compress:
                h = hashlib.md5(content.encode()).hexdigest()
                key = f"{entry.rel_path}:{h}"
                if key in cache:
                    final_content = cache[key]
                    new_cache[key] = final_content
                else:
                    final_content = compress_content(cfg, content, entry.rel_path)
                    new_cache[key] = final_content
            
            # Token count
            tokens = count_tokens(final_content)
            total_tokens += tokens
            entry.tokens = tokens
            
            lang = entry.path.suffix.lstrip('.') or "txt"
            output_lines.append(f"\n## File: {entry.rel_path}")
            output_lines.append(f"Tokens: {tokens} | Size: {entry.size}b")
            output_lines.append(f"```{lang}\n{final_content}\n```")
            
        except Exception as e:
            output_lines.append(f"## {entry.rel_path} (Error reading: {e})")

    # Save cache
    if cfg.compress:
        try:
            cache_path.write_text(json.dumps(new_cache))
        except Exception:
            pass

    summary_text = "\n".join(output_lines)
    output_path = cfg.summary_dir / OUTPUT_FILE
    output_path.write_text(summary_text, encoding='utf-8')

    return {
        "summary": summary_text,
        "path": str(output_path),
        "files": len(entries),
        "tokens": total_tokens
    }

# --- Interfaces ---

def run_mcp(cfg: Config):
    """MCP JSON Output Mode."""
    res = generate_summary(cfg)
    if "error" in res:
        print(json.dumps({"error": res["error"]}), file=sys.stderr)
        sys.exit(1)
    
    # MCP expects the result printed? Or specific JSON format? 
    # Based on input, it returns a JSON object with specific keys or just summary.
    # The original codesum-mcp.py printed the summary to stdout.
    
    # We output the raw summary for Claude to read directly
    print(res["summary"])
    
    # Log metadata to stderr
    log = f"✓ Files: {res['files']} | Tokens: ~{res['tokens']:,} | Path: {res['path']}"
    print(log, file=sys.stderr)

def run_cli(cfg: Config):
    """Interactive CLI Mode."""
    print(f"🔍 Scanning {cfg.root}...")
    res = generate_summary(cfg)
    
    if "error" in res:
        print(f"❌ {res['error']}")
        sys.exit(1)

    print(f"\n✅ Summary generated at: {res['path']}")
    print(f"📊 Stats: {res['files']} files | ~{res['tokens']:,} tokens")
    
    # Try clipboard
    try:
        if subprocess.run(['which', 'wl-copy'], capture_output=True).returncode == 0:
            subprocess.run(['wl-copy'], input=res['summary'].encode(), check=True)
            print("📋 Copied to clipboard.")
    except Exception:
        pass

def main():
    parser = argparse.ArgumentParser(description="Codesum: Optimize Code Context")
    parser.add_argument("root", nargs="?", default=".", help="Project root")
    parser.add_argument("--mcp", action="store_true", help="Run in MCP mode (JSON/Text output)")
    parser.add_argument("--hook", action="store_true", help="Run as Git/Session hook (Silent)")
    parser.add_argument("--compress", "-c", action="store_true", help="Enable AI compression")
    parser.add_argument("--api-key", help="OpenAI API Key")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Error: {root} does not exist", file=sys.stderr)
        sys.exit(1)

    summary_dir = root / SUMMARY_DIR
    summary_dir.mkdir(parents=True, exist_ok=True)

    cfg = Config(
        root=root,
        summary_dir=summary_dir,
        mode="mcp" if args.mcp else ("hook" if args.hook else "cli"),
        compress=args.compress,
        api_key=args.api_key or os.getenv("OPENAI_API_KEY"),
        ignore_patterns=parse_gitignore(root)
    )

    if args.mcp:
        run_mcp(cfg)
    elif args.hook:
        # Hook mode just runs and exits silently unless error
        res = generate_summary(cfg)
        if "error" in res:
            sys.exit(1)
        print(res["path"]) # Hook expects path on stdout usually
    else:
        run_cli(cfg)

if __name__ == "__main__":
    sys.exit(main())
