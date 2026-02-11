#!/usr/bin/env python3
"""
Snapchat memories_history.json downloader (stdlib-only).

Features:
  - CLI flags + optional curses TUI for selecting JSON + output dir
  - Atomic streaming downloads (.part -> final)
  - ZIP extraction for captioned memories (caption.png, image.jpg, video.mp4)
  - Collision-safe filenames (timestamp-based)
  - Parallel downloads with retry/backoff
  - Optional filtering (video/image), dry-run, skip-existing

Examples:
  python3 -O snap-mem.py --json /path/memories_history.json --out /path/out
  python3 -O snap-mem.py   # interactive TUI if TTY
"""

from __future__ import annotations

import argparse
import curses
import json
import os
import re
import shutil
import sys
import threading
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING, Final
from urllib.error import HTTPError, URLError
from urllib.request import OpenerDirector, Request, build_opener

if TYPE_CHECKING:
  from curses import window as CursesWindow

DATE_FMT: Final[str] = "%Y-%m-%d %H:%M:%S UTC"
JSON_NAME_RE: Final[re.Pattern[str]] = re.compile(r"memories_history\.json$", re.I)
CHUNK_SIZE: Final[int] = 1048576
MACOS_JUNK_RE: Final[re.Pattern[str]] = re.compile(r"^\._")

@dataclass(frozen=True, slots=True)
class Item:
  date_str: str
  url: str
  is_video: bool

def die(msg: str, code: int = 1) -> None:
  print(msg, file=sys.stderr)
  raise SystemExit(code)

def parse_args(argv: list[str]) -> argparse.Namespace:
  p = argparse.ArgumentParser(prog="snap-mem.py", description="Download Snapchat Saved Media from memories_history.json (stdlib only).")
  p.add_argument("--json", dest="json_path", default="", help="Path to memories_history.json")
  p.add_argument("--out", dest="out_dir", default="", help="Output directory for downloads")
  p.add_argument("--type", dest="media_type", default="all", choices=["all", "video", "image"], help="Filter media type")
  p.add_argument("--dry-run", action="store_true", help="List what would be downloaded")
  p.add_argument("--skip-existing", action="store_true", help="Skip if target file already exists")
  p.add_argument("--timeout", type=float, default=30.0, help="HTTP timeout seconds")
  p.add_argument("--retries", type=int, default=3, help="Retries per file")
  p.add_argument("--retry-backoff", type=float, default=1.0, help="Base backoff seconds")
  p.add_argument("--user-agent", default="Mozilla/5.0 (SnapchatMemoryDownloader; +stdlib)", help="User-Agent header")
  p.add_argument("--no-tui", action="store_true", help="Disable TUI prompts; require flags")
  p.add_argument("--workers", type=int, default=4, help="Number of parallel download workers (default: 4)")
  return p.parse_args(argv)

def load_items(json_path: Path, media_type: str) -> list[Item]:
  try:
    with json_path.open("r", encoding="utf-8") as f:
      try:
        data = json.load(f)
      except json.JSONDecodeError as e:
        die(f"Invalid JSON: {json_path}\n{e}")
  except OSError as e:
    die(f"Failed to read JSON: {json_path}\n{e}")
  media_items = data.get("Saved Media", [])
  if not isinstance(media_items, list):
    die('JSON missing "Saved Media" list')
  out: list[Item] = []
  want_video, want_image = media_type == "video", media_type == "image"
  for obj in media_items:
    if not isinstance(obj, dict):
      continue
    mt = str(obj.get("Media Type", "")).lower()
    is_video = mt == "video"
    if (want_video and not is_video) or (want_image and is_video):
      continue
    date_str, url = obj.get("Date"), obj.get("Media Download Url")
    if not isinstance(date_str, str) or not date_str:
      continue
    if not isinstance(url, str) or not url.startswith(("http://", "https://")):
      continue
    out.append(Item(date_str=date_str, url=url, is_video=is_video))
  return out

def build_base_name(date_str: str) -> str:
  dt = datetime.strptime(date_str, DATE_FMT)
  return dt.strftime("%Y-%m-%d_%H-%M-%S")

def make_unique_name(base: str, suffix: str, existing: set[str], lock: threading.Lock) -> str:
  with lock:
    name = f"{base}{suffix}"
    n = 1
    while name in existing:
      name = f"{base}_{n}{suffix}"
      n += 1
    existing.add(name)
    return name

def tui_select_path(*, title: str, start: Path, mode: str) -> Path:
  if not sys.stdin.isatty() or not sys.stdout.isatty():
    die("TUI requires TTY. Use --json/--out or --no-tui.")
  if mode not in ("file", "dir"):
    raise ValueError("mode must be 'file' or 'dir'")
  start = start.expanduser().resolve() if start.exists() else Path.cwd().resolve()
  def run(stdscr: CursesWindow) -> Path:
    curses.curs_set(0)
    stdscr.keypad(True)
    cwd, idx = start, 0
    last_cwd: Path | None = None
    entries: list[Path] = []
    while True:
      if cwd != last_cwd:
        try:
          entries = sorted([p for p in cwd.iterdir() if not p.name.startswith(".")], key=lambda p: (not p.is_dir(), p.name.lower()))
        except OSError:
          entries = []
        last_cwd = cwd
      shown: list[Path] = [cwd.parent, *entries]
      idx = min(idx, max(0, len(shown) - 1))
      stdscr.erase()
      h, w = stdscr.getmaxyx()
      stdscr.addnstr(0, 0, f"{title} [{mode}] cwd: {cwd}", w - 1)
      stdscr.addnstr(1, 0, "↑↓/jk: move Enter: select Backspace: up q: quit", w - 1)
      row0, max_rows = 3, max(1, h - 4)
      top = max(0, idx - max_rows + 1)
      for i in range(top, min(len(shown), top + max_rows)):
        p = shown[i]
        name = ".." if i == 0 else p.name + ("/" if p.is_dir() else "")
        attr = curses.A_REVERSE if i == idx else 0
        stdscr.addnstr(row0 + i - top, 0, name, w - 1, attr)
      stdscr.refresh()
      k = stdscr.getch()
      if k in (ord("q"), 27):
        raise KeyboardInterrupt
      if k in (curses.KEY_UP, ord("k")):
        idx = max(0, idx - 1)
      elif k in (curses.KEY_DOWN, ord("j")):
        idx = min(len(shown) - 1, idx + 1)
      elif k in (curses.KEY_BACKSPACE, 127, 8):
        cwd, idx = cwd.parent, 0
      elif k in (curses.KEY_ENTER, 10, 13):
        pick = shown[idx]
        if idx == 0:
          cwd, idx = cwd.parent, 0
        elif pick.is_dir():
          if mode == "dir":
            return pick
          cwd, idx = pick, 0
        elif mode == "file" and JSON_NAME_RE.search(pick.name):
          return pick
    return cwd
  try:
    return curses.wrapper(run)
  except KeyboardInterrupt:
    die("Aborted.")

def download_to_path(*, opener: OpenerDirector, url: str, dest: Path, timeout: float, user_agent: str) -> None:
  tmp = dest.with_suffix(dest.suffix + ".part")
  req = Request(url, headers={"User-Agent": user_agent})
  with opener.open(req, timeout=timeout) as r, open(tmp, "wb") as f:
    while chunk := r.read(CHUNK_SIZE):
      f.write(chunk)
  os.replace(tmp, dest)

def download_with_retries(*, opener: OpenerDirector, url: str, dest: Path, timeout: float, user_agent: str, retries: int, backoff: float) -> None:
  last_exc: Exception | None = None
  for attempt in range(retries + 1):
    try:
      download_to_path(opener=opener, url=url, dest=dest, timeout=timeout, user_agent=user_agent)
      return
    except (HTTPError, URLError, TimeoutError, OSError) as e:
      last_exc = e
      if attempt < retries:
        time.sleep(backoff * (2**attempt))
  if last_exc:
    raise last_exc
  raise RuntimeError("download failed")

def extract_zip_atomically(zip_path: Path, base_name: str, out_dir: Path, existing: set[str], lock: threading.Lock) -> list[str]:
  extracted: list[str] = []
  try:
    with zipfile.ZipFile(zip_path, "r") as z:
      for member in z.infolist():
        # Skip directories and nested files to match original flat behavior
        if member.is_dir() or '/' in member.filename or '\\' in member.filename:
          continue
        if MACOS_JUNK_RE.match(member.filename):
          continue

        lname = member.filename.lower()
        if lname.endswith(".png"):
          suffix = "_caption.png"
        elif lname.endswith(".jpg"):
          suffix = "_image.jpg"
        elif lname.endswith(".mp4"):
          suffix = "_video.mp4"
        else:
          continue

        final_name = make_unique_name(base_name, suffix, existing, lock)
        target_path = out_dir / final_name
        # Use .part suffix for atomicity
        temp_path = target_path.with_suffix(target_path.suffix + ".part")

        with z.open(member) as source, open(temp_path, "wb") as target:
          shutil.copyfileobj(source, target)

        os.replace(temp_path, target_path)
        extracted.append(final_name)
  finally:
    zip_path.unlink(missing_ok=True)
  return extracted

def main(argv: list[str]) -> int:
  ns = parse_args(argv)
  json_path_s = ns.json_path.strip().strip('"\'')
  out_dir_s = ns.out_dir.strip().strip('"\'')
  json_path: Path | None = Path(json_path_s) if json_path_s else None
  out_dir: Path | None = Path(out_dir_s) if out_dir_s else None
  if json_path is None and not ns.no_tui:
    json_path = tui_select_path(title="Select memories_history.json", start=Path.cwd(), mode="file")
  if out_dir is None and not ns.no_tui:
    out_dir = tui_select_path(title="Select output directory", start=Path.cwd(), mode="dir")
  if json_path is None:
    die("Missing --json (or omit --no-tui for TUI).")
  if out_dir is None:
    die("Missing --out (or omit --no-tui for TUI).")
  json_path, out_dir = json_path.expanduser(), out_dir.expanduser()
  if not json_path.is_file():
    die(f"JSON does not exist: {json_path}")
  out_dir.mkdir(parents=True, exist_ok=True)
  items = load_items(json_path, ns.media_type)
  if not items:
    print("No media items found.")
    return 0
  existing = {p.name for p in out_dir.iterdir() if p.is_file()}
  existing_prefixes = {name.rsplit("_", 1)[0] if "_" in name else name.rsplit(".", 1)[0] for name in existing}
  lock = threading.Lock()
  opener = build_opener()
  download_tasks: list[tuple[Item, str]] = []
  for it in items:
    try:
      base = build_base_name(it.date_str)
    except ValueError as e:
      print(f"FAIL bad date '{it.date_str}': {e}", file=sys.stderr)
      continue
    if ns.skip_existing and base in existing_prefixes:
      continue
    download_tasks.append((it, base))
  if ns.dry_run:
    for it, base in download_tasks:
      print(f"DRY {base} <- {it.url}")
    print(f"Done. Would download {len(download_tasks)} files.")
    return 0
  ok, failed = 0, 0
  def download_item(task: tuple[Item, str]) -> bool:
    it, base = task
    zip_path = out_dir / f"{base}_memory.zip"
    try:
      download_with_retries(opener=opener, url=it.url, dest=zip_path, timeout=ns.timeout, user_agent=ns.user_agent, retries=ns.retries, backoff=ns.retry_backoff)
      if zipfile.is_zipfile(zip_path):
        extracted = extract_zip_atomically(zip_path, base, out_dir, existing, lock)
        for name in extracted:
          print(f"✓ {name}")
      else:
        ext = ".mp4" if it.is_video else ".jpg"
        final_name = make_unique_name(base, ext, existing, lock)
        os.replace(zip_path, out_dir / final_name)
        print(f"✓ {final_name}")
      return True
    except (HTTPError, URLError, TimeoutError, OSError) as e:
      print(f"✗ {base}: {e}", file=sys.stderr)
      zip_path.unlink(missing_ok=True)
      return False
  with ThreadPoolExecutor(max_workers=ns.workers) as executor:
    futures = {executor.submit(download_item, task): task for task in download_tasks}
    for future in as_completed(futures):
      if future.result():
        ok += 1
      else:
        failed += 1
  skipped = len(items) - len(download_tasks)
  print(f"Done. ok={ok} skipped={skipped} failed={failed}")
  return 0 if failed == 0 else 2

if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
