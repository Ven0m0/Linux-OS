#!/usr/bin/env python3
"""
Enhanced Code Summarizer - Multi-LLM + Traceback Analysis.
Features: AST extraction, traceback parsing, Gemini/Claude/OpenAI APIs, pattern matching.
Deps: None (Optional: openai, anthropic, google-generativeai, tiktoken).
"""

from __future__ import annotations

import argparse
import ast
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, List, Optional, Pattern, Any, Dict, Tuple

# Optional imports
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

try:
    from anthropic import Anthropic

    HAS_ANTHROPIC = True
except ImportError:
    HAS_ANTHROPIC = False

try:
    import google.generativeai as genai

    HAS_GEMINI = True
except ImportError:
    HAS_GEMINI = False

# Constants
SUMMARY_DIR = ".summary_files"
OUTPUT_FILE = "code_summary.md"
CACHE_FILE = "cache.json"

DEFAULT_IGNORES = [
    ".git",
    ".svn",
    ".hg",
    "venv",
    ".venv",
    "env",
    "__pycache__",
    ".vscode",
    ".idea",
    ".ds_store",
    "node_modules",
    "bower_components",
    "build",
    "dist",
    "target",
    "out",
    "coverage",
    ".tox",
    "*.pyc",
    "*.pyo",
    "*.pyd",
    "*.so",
    "*.dll",
    "*.exe",
    "*.bin",
    "*.egg-info",
    "*.lock",
    "package-lock.json",
    "yarn.lock",
    SUMMARY_DIR,
]

BINARY_EXTS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".ico",
    ".webp",
    ".svg",
    ".mp3",
    ".mp4",
    ".wav",
    ".avi",
    ".mov",
    ".mkv",
    ".zip",
    ".tar",
    ".gz",
    ".7z",
    ".rar",
    ".pdf",
    ".db",
    ".sqlite",
    ".parquet",
    ".pkl",
}


@dataclass(slots=True)
class FileEntry:
    path: Path
    rel_path: str
    size: int
    tokens: int = 0
    is_python: bool = False


@dataclass(slots=True)
class FunctionInfo:
    name: str
    args: str
    return_type: str

    def __str__(self):
        return f"{self.name}({self.args}) -> {self.return_type}"


@dataclass
class Config:
    root: Path
    summary_dir: Path
    mode: str = "cli"
    compress: bool = False
    llm_provider: str = "openai"  # openai, gemini, claude
    api_key: Optional[str] = None
    model: str = "gpt-4o-mini"
    ignore_patterns: List[str] = field(default_factory=list)
    print_full: List[str] = field(default_factory=list)
    traceback: Optional[str] = None
    remote_url: Optional[str] = None
    _compiled_ignores: List[Pattern] = field(default_factory=list, init=False)

    def __post_init__(self):
        combined = DEFAULT_IGNORES + self.ignore_patterns
        self._compiled_ignores = [re.compile(fnmatch.translate(p)) for p in combined]


# AST Extraction
def get_function_info(func_def: ast.FunctionDef) -> FunctionInfo:
    """Extract function signature from AST."""
    args_str = ", ".join(
        arg.arg + (f": {ast.unparse(arg.annotation)}" if arg.annotation else "")
        for arg in func_def.args.args
    )
    ret = ast.unparse(func_def.returns) if func_def.returns else "None"
    return FunctionInfo(name=func_def.name, args=args_str, return_type=ret)


def extract_python_structure(path: Path) -> str:
    """Extract classes/functions from Python file using AST."""
    try:
        code = path.read_text(encoding="utf-8", errors="ignore")
        tree = ast.parse(code)
        items = []
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                info = get_function_info(node)
                items.append(str(info))
            elif isinstance(node, ast.ClassDef):
                methods = [
                    get_function_info(m)
                    for m in node.body
                    if isinstance(m, ast.FunctionDef)
                ]
                items.append(f"class {node.name}: {', '.join(str(m) for m in methods)}")
        return "\n".join(items) if items else code[:500]
    except Exception:
        return ""


# Traceback Parser
def parse_traceback(tb_str: str) -> List[Dict[str, Any]]:
    """Parse Python traceback into structured data."""
    pattern = re.compile(r'^\s*File "([^"]+)", line (\d+)(?:, in (\w+))?.*$')
    frames = []
    for line in tb_str.splitlines():
        match = pattern.match(line)
        if match:
            file_path, line_num, func = match.groups()
            frames.append(
                {"file": file_path, "line": int(line_num), "function": func or "?"}
            )
    return frames


def get_function_context(path: Path, line_num: int) -> Optional[str]:
    """Get function context for line number using AST."""
    try:
        code = path.read_text(encoding="utf-8", errors="ignore")
        tree = ast.parse(code)
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                if node.lineno <= line_num <= (node.end_lineno or 999999):
                    func_lines = code.splitlines()[node.lineno - 1 : node.end_lineno]
                    return "\n".join(func_lines[:20])
    except Exception:
        pass
    return None


def get_line_context(path: Path, line_num: int, ctx: int = 3) -> List[Tuple[int, str]]:
    """Get surrounding lines of code."""
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        start = max(0, line_num - ctx - 1)
        end = min(len(lines), line_num + ctx)
        return [(i + 1, lines[i]) for i in range(start, end)]
    except Exception:
        return []


def format_traceback_context(tb_str: str, root: Path) -> str:
    """Format traceback with extracted context."""
    frames = parse_traceback(tb_str)
    if not frames:
        return "No traceback parsed."

    output = []
    for frame in frames:
        file_path = Path(frame["file"])
        if not file_path.is_absolute():
            file_path = root / file_path

        output.append(
            f"File: {frame['file']}, Line: {frame['line']}, Function: {frame['function']}"
        )

        if file_path.exists():
            func_ctx = get_function_context(file_path, frame["line"])
            if func_ctx:
                output.append("Function Context:")
                output.append(f"```python\n{func_ctx}\n```")

            line_ctx = get_line_context(file_path, frame["line"])
            if line_ctx:
                output.append("Line Context:")
                for num, line in line_ctx:
                    marker = ">>>" if num == frame["line"] else "   "
                    output.append(f"{marker} {num:4d}: {line}")
        output.append("")

    return "\n".join(output)


# File Operations
def is_binary(path: Path) -> bool:
    """Fast binary check."""
    if path.suffix.lower() in BINARY_EXTS:
        return True
    try:
        with path.open("rb") as f:
            return b"\x00" in f.read(1024)
    except OSError:
        return True


def parse_gitignore(root: Path) -> List[str]:
    """Extract patterns from .gitignore."""
    patterns = []
    gitignore = root / ".gitignore"
    if gitignore.is_file():
        try:
            for line in gitignore.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    patterns.append(line.lstrip("/"))
        except OSError:
            pass
    return patterns


def should_ignore(rel_path: str, cfg: Config) -> bool:
    """Check if path matches ignore patterns."""
    name = os.path.basename(rel_path)
    for pattern in cfg._compiled_ignores:
        if pattern.match(rel_path) or pattern.match(name):
            return True
    return False


def matches_pattern(rel_path: str, patterns: List[str]) -> bool:
    """Check if path matches any of the given patterns."""
    return any(fnmatch.fnmatch(rel_path, p) for p in patterns)


def collect_files(cfg: Config) -> Iterator[FileEntry]:
    """Walk directory and collect text files."""
    root_str = str(cfg.root)
    for root, dirs, files in os.walk(root_str, topdown=True):
        rel_root = os.path.relpath(root, root_str)
        if rel_root == ".":
            rel_root = ""

        dirs[:] = [d for d in dirs if not should_ignore(os.path.join(rel_root, d), cfg)]

        for name in files:
            rel_path = os.path.join(rel_root, name) if rel_root else name
            if should_ignore(rel_path, cfg):
                continue

            full_path = Path(root) / name
            if is_binary(full_path):
                continue

            try:
                stat = full_path.stat()
                if stat.st_size > 1_000_000:
                    continue
                yield FileEntry(
                    path=full_path,
                    rel_path=rel_path,
                    size=stat.st_size,
                    is_python=full_path.suffix == ".py",
                )
            except OSError:
                continue


def clone_repo(url: str) -> Optional[Path]:
    """Clone GitHub repo to temp dir."""
    try:
        tmpdir = Path(tempfile.mkdtemp())
        subprocess.run(
            ["git", "clone", "--depth", "1", url, str(tmpdir)],
            check=True,
            capture_output=True,
        )
        return tmpdir
    except Exception as e:
        sys.stderr.write(f"Clone failed: {e}\n")
        return None


# LLM APIs
def count_tokens(text: str) -> int:
    """Token counting."""
    if HAS_TIKTOKEN:
        try:
            enc = tiktoken.get_encoding("o200k_base")
            return len(enc.encode(text))
        except Exception:
            pass
    return len(text) // 4


def compress_openai(text: str, api_key: str, model: str) -> str:
    """OpenAI compression."""
    if not HAS_OPENAI:
        return text
    try:
        client = OpenAI(api_key=api_key)
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "system",
                    "content": "Minify code. Keep signatures/logic. Remove comments/whitespace.",
                },
                {"role": "user", "content": text},
            ],
            max_tokens=2000,
            temperature=0,
        )
        return resp.choices[0].message.content or text
    except Exception as e:
        sys.stderr.write(f"OpenAI err: {e}\n")
        return text


def compress_gemini(text: str, api_key: str, model: str) -> str:
    """Gemini compression via HTTP."""
    try:
        url = f"https://generativelanguage.googleapis.com/v1/models/{model}:generateContent?key={api_key}"
        data = json.dumps(
            {
                "contents": [
                    {"parts": [{"text": f"Minify this code, keep logic:\n{text}"}]}
                ],
                "generationConfig": {"maxOutputTokens": 2000, "temperature": 0},
            }
        ).encode()
        req = urllib.request.Request(
            url, data=data, headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return result["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        sys.stderr.write(f"Gemini err: {e}\n")
        return text


def compress_claude(text: str, api_key: str, model: str) -> str:
    """Claude compression via HTTP."""
    try:
        url = "https://api.anthropic.com/v1/messages"
        data = json.dumps(
            {
                "model": model,
                "max_tokens": 2000,
                "messages": [
                    {
                        "role": "user",
                        "content": f"Minify this code, keep logic:\n{text}",
                    }
                ],
            }
        ).encode()
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "Content-Type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return result["content"][0]["text"]
    except Exception as e:
        sys.stderr.write(f"Claude err: {e}\n")
        return text


def compress_content(cfg: Config, text: str) -> str:
    """Multi-provider compression."""
    if not (cfg.compress and cfg.api_key):
        return text

    if cfg.llm_provider == "openai":
        return compress_openai(text, cfg.api_key, cfg.model)
    elif cfg.llm_provider == "gemini":
        return compress_gemini(text, cfg.api_key, cfg.model)
    elif cfg.llm_provider == "claude":
        return compress_claude(text, cfg.api_key, cfg.model)
    return text


# Summary Generation
def generate_tree(files: List[FileEntry]) -> str:
    """Generate directory tree."""
    lines = []
    seen = set()
    for f in sorted(files, key=lambda x: x.rel_path):
        parts = f.rel_path.split(os.sep)
        for i in range(len(parts)):
            path = os.sep.join(parts[: i + 1])
            if path in seen:
                continue
            seen.add(path)
            indent = "  " * i
            lines.append(f"{indent}├── {parts[i]}")
    return "\n".join(lines[:200])


def generate_summary(cfg: Config) -> Dict[str, Any]:
    """Main summary generation."""
    entries = list(collect_files(cfg))
    if not entries:
        return {"error": "No text files found."}

    cache_path = cfg.summary_dir / CACHE_FILE
    cache = {}
    if cfg.compress and cache_path.exists():
        try:
            cache = json.loads(cache_path.read_text())
        except Exception:
            pass

    output = [
        f"# Project Summary: {cfg.root.name}",
        f"Files: {len(entries)} | Mode: {'Compressed' if cfg.compress else 'Raw'} | LLM: {cfg.llm_provider}",
        "\n## Structure",
        "```text",
        generate_tree(entries),
        "```",
        "\n---",
    ]

    total_tokens = 0
    new_cache = {}

    for entry in entries:
        try:
            # Decide content format
            if matches_pattern(entry.rel_path, cfg.print_full):
                content = entry.path.read_text(encoding="utf-8", errors="ignore")
            elif entry.is_python:
                content = (
                    extract_python_structure(entry.path)
                    or entry.path.read_text(encoding="utf-8", errors="ignore")[:500]
                )
            else:
                content = entry.path.read_text(encoding="utf-8", errors="ignore")[:500]

            # Compression
            final = content
            if cfg.compress:
                h = hashlib.md5(content.encode()).hexdigest()
                key = f"{entry.rel_path}:{h}"
                if key in cache:
                    final = cache[key]
                else:
                    final = compress_content(cfg, content)
                    new_cache[key] = final

            tokens = count_tokens(final)
            total_tokens += tokens
            entry.tokens = tokens

            lang = entry.path.suffix.lstrip(".") or "txt"
            output.append(f"\n## File: {entry.rel_path}")
            output.append(f"Tokens: {tokens} | Size: {entry.size}b")
            output.append(f"```{lang}\n{final}\n```")
        except Exception as e:
            output.append(f"## {entry.rel_path} (Error: {e})")

    # Traceback
    if cfg.traceback:
        output.append("\n---\n## Traceback Analysis")
        output.append(f"```\n{cfg.traceback}\n```")
        tb_ctx = format_traceback_context(cfg.traceback, cfg.root)
        output.append(f"\n### Context\n{tb_ctx}")
        output.append("\nResolve this error.")

    if cfg.compress:
        try:
            cache_path.write_text(json.dumps(new_cache))
        except Exception:
            pass

    summary_text = "\n".join(output)
    output_path = cfg.summary_dir / OUTPUT_FILE
    output_path.write_text(summary_text, encoding="utf-8")

    return {
        "summary": summary_text,
        "path": str(output_path),
        "files": len(entries),
        "tokens": total_tokens,
    }


# Interfaces
def run_mcp(cfg: Config):
    """MCP mode."""
    res = generate_summary(cfg)
    if "error" in res:
        print(json.dumps({"error": res["error"]}), file=sys.stderr)
        sys.exit(1)
    print(res["summary"])
    log = f"✓ Files: {res['files']} | Tokens: ~{res['tokens']:,} | Path: {res['path']}"
    print(log, file=sys.stderr)


def run_cli(cfg: Config):
    """CLI mode."""
    print(f"🔍 Scanning {cfg.root}...")
    res = generate_summary(cfg)

    if "error" in res:
        print(f"❌ {res['error']}")
        sys.exit(1)

    print(f"\n✅ Summary: {res['path']}")
    print(f"📊 Stats: {res['files']} files | ~{res['tokens']:,} tokens")

    try:
        if subprocess.run(["which", "wl-copy"], capture_output=True).returncode == 0:
            subprocess.run(["wl-copy"], input=res["summary"].encode(), check=True)
            print("📋 Copied to clipboard.")
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser(description="Enhanced Code Summarizer")
    parser.add_argument(
        "root", nargs="?", default=".", help="Project root or GitHub URL"
    )
    parser.add_argument("--mcp", action="store_true", help="MCP mode")
    parser.add_argument("--hook", action="store_true", help="Hook mode (silent)")
    parser.add_argument(
        "-c", "--compress", action="store_true", help="Enable AI compression"
    )
    parser.add_argument(
        "--llm",
        choices=["openai", "gemini", "claude"],
        default="openai",
        help="LLM provider",
    )
    parser.add_argument("--api-key", help="API key")
    parser.add_argument("--model", help="Model name")
    parser.add_argument(
        "--print-full", nargs="+", default=[], help="Patterns for full file content"
    )
    parser.add_argument("-i", "--ignore", nargs="+", default=[], help="Ignore patterns")
    parser.add_argument("-t", "--traceback", help="Traceback string for analysis")
    args = parser.parse_args()

    root_input = args.root
    is_remote = root_input.startswith("http")

    if is_remote:
        print(f"Cloning {root_input}...")
        root = clone_repo(root_input)
        if not root:
            sys.exit(1)
    else:
        root = Path(root_input).resolve()
        if not root.exists():
            print(f"Error: {root} does not exist", file=sys.stderr)
            sys.exit(1)

    summary_dir = root / SUMMARY_DIR
    summary_dir.mkdir(parents=True, exist_ok=True)

    # Auto-detect API keys
    api_key = args.api_key
    if not api_key:
        if args.llm == "openai":
            api_key = os.getenv("OPENAI_API_KEY")
        elif args.llm == "gemini":
            api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
        elif args.llm == "claude":
            api_key = os.getenv("ANTHROPIC_API_KEY") or os.getenv("CLAUDE_API_KEY")

    # Model defaults
    model = args.model
    if not model:
        if args.llm == "openai":
            model = "gpt-4o-mini"
        elif args.llm == "gemini":
            model = "gemini-1.5-flash"
        elif args.llm == "claude":
            model = "claude-3-5-haiku-20241022"

    cfg = Config(
        root=root,
        summary_dir=summary_dir,
        mode="mcp" if args.mcp else ("hook" if args.hook else "cli"),
        compress=args.compress,
        llm_provider=args.llm,
        api_key=api_key,
        model=model,
        ignore_patterns=args.ignore + parse_gitignore(root),
        print_full=args.print_full,
        traceback=args.traceback,
        remote_url=root_input if is_remote else None,
    )

    try:
        if args.mcp:
            run_mcp(cfg)
        elif args.hook:
            res = generate_summary(cfg)
            if "error" in res:
                sys.exit(1)
            print(res["path"])
        else:
            run_cli(cfg)
    finally:
        if is_remote and root:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
