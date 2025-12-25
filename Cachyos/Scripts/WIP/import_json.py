#!/usr/bin/env python3
"""
Snapchat memories_history. json downloader (stdlib-only).

Features:
  - CLI flags + optional curses TUI for selecting JSON + output dir
  - Atomic streaming downloads (. part -> final)
  - Collision-safe filenames (timestamp-based)
  - Optional filtering (video/image), dry-run, skip-existing, retries/backoff

Examples:
  python3 -OO import_json.py --json /path/memories_history.json --out /path/out
  python3 -OO import_json.py   # interactive TUI if TTY
"""
from __future__ import annotations

import argparse
import curses
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING, Final
from urllib.error import HTTPError, URLError
from urllib.request import OpenerDirector, Request, build_opener

if TYPE_CHECKING:
  from curses import window as CursesWindow

DATE_FMT: Final[str] = "%Y-%m-%d %H:%M:%S UTC"
JSON_NAME_RE: Final[re.Pattern[str]] = re. compile(r"memories_history\.json$", re.I)


@dataclass(frozen=True, slots=True)
class Item:
  date_str: str
  url: str
  ext: str


def die(msg: str, code: int = 1) -> None:
  print(msg, file=sys. stderr)
  raise SystemExit(code)


def dequote_dragdrop(s: str) -> str:
  s = s.strip()
  if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
    return s[1:-1]
  return s


def parse_args(argv: list[str]) -> argparse.Namespace:
  p = argparse.ArgumentParser(
    prog="import_json. py",
    description="Download Snapchat Saved Media from memories_history.json (stdlib only).",
  )
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
  return p.parse_args(argv)


def load_items(json_path:  Path, media_type: str) -> list[Item]:
  try:
    raw = json_path.read_text(encoding="utf-8")
  except OSError as e: 
    die(f"Failed to read JSON file: {json_path}\n{e}")
  try:
    data = json.loads(raw)
  except json.JSONDecodeError as e: 
    die(f"Invalid JSON:  {json_path}\n{e}")
  media_items = data.get("Saved Media", [])
  if not isinstance(media_items, list):
    die('JSON does not contain expected list at key "Saved Media"')
  out:  list[Item] = []
  want_video, want_image = media_type == "video", media_type == "image"
  for obj in media_items: 
    if not isinstance(obj, dict):
      continue
    mt = str(obj.get("Media Type", "")).lower()
    is_video = mt == "video"
    if want_video and not is_video: 
      continue
    if want_image and is_video:
      continue
    date_str, url = obj.get("Date"), obj.get("Media Download Url")
    if not isinstance(date_str, str) or not date_str: 
      continue
    if not isinstance(url, str) or not url. startswith(("http://", "https://")):
      continue
    out.append(Item(date_str=date_str, url=url, ext=". mp4" if is_video else ".jpg"))
  return out


def build_filename(date_str: str, ext: str, existing: set[str]) -> str:
  dt = datetime.strptime(date_str, DATE_FMT)
  base = dt.strftime("%Y-%m-%d_%H-%M-%S")
  name = f"{base}{ext}"
  n = 1
  while name in existing:
    name = f"{base}_{n}{ext}"
    n += 1
  return name


def list_dir_entries(dirpath: Path) -> list[Path]: 
  try:
    entries = [p for p in dirpath.iterdir() if not p.name.startswith(".")]
  except OSError: 
    return []
  entries.sort(key=lambda p:  (not p.is_dir(), p.name.lower()))
  return entries


def tui_select_path(*, title: str, start:  Path, mode: str) -> Path:
  if not sys.stdin.isatty() or not sys.stdout.isatty():
    die("TUI requires a TTY.  Provide --json/--out or use --no-tui.")
  if mode not in ("file", "dir"):
    raise ValueError("mode must be 'file' or 'dir'")
  start = start.expanduser().resolve() if start.exists() else Path. cwd().resolve()

  def run(stdscr: CursesWindow) -> Path:
    curses.curs_set(0)
    stdscr.keypad(True)
    cwd, idx = start, 0
    while True:
      entries = list_dir_entries(cwd)
      shown:  list[Path] = [cwd. parent, *entries]
      idx = min(idx, max(0, len(shown) - 1))
      stdscr.erase()
      h, w = stdscr.getmaxyx()
      stdscr. addnstr(0, 0, f"{title}  [{mode}]  cwd:  {cwd}", w - 1)
      stdscr.addnstr(1, 0, "↑↓/jk:  move  Enter: select  Backspace: up  q: quit", w - 1)
      row0, max_rows = 3, max(1, h - 4)
      top = max(0, idx - max_rows + 1)
      for i in range(top, min(len(shown), top + max_rows)):
        p = shown[i]
        name = ". ." if i == 0 else p. name + ("/" if p.is_dir() else "")
        attr = curses.A_REVERSE if i == idx else 0
        stdscr.addnstr(row0 + i - top, 0, name, w - 1, attr)
      stdscr.refresh()
      k = stdscr. getch()
      if k in (ord("q"), 27):
        raise KeyboardInterrupt
      if k in (curses.KEY_UP, ord("k")):
        idx = max(0, idx - 1)
      elif k in (curses.KEY_DOWN, ord("j")):
        idx = min(len(shown) - 1, idx + 1)
      elif k in (curses.KEY_BACKSPACE, 127, 8):
        cwd, idx = cwd. parent, 0
      elif k in (curses.KEY_ENTER, 10, 13):
        pick = shown[idx]
        if idx == 0:
          cwd, idx = cwd. parent, 0
        elif pick.is_dir():
          if mode == "dir": 
            return pick
          cwd, idx = pick, 0
        elif mode == "file" and JSON_NAME_RE. search(pick.name):
          return pick
    return cwd  # unreachable, satisfies type checker

  try:
    return curses.wrapper(run)
  except KeyboardInterrupt: 
    die("Aborted.")


def download_to_path(
  *,
  opener: OpenerDirector,
  url:  str,
  dest: Path,
  timeout: float,
  user_agent: str,
) -> None:
  tmp = dest. with_suffix(dest.suffix + ". part")
  req = Request(url, headers={"User-Agent": user_agent})
  with opener. open(req, timeout=timeout) as r:
    with open(tmp, "wb") as f:
      while chunk := r.read(524288):
        f.write(chunk)
  os.replace(tmp, dest)


def download_with_retries(
  *,
  opener:  OpenerDirector,
  url: str,
  dest:  Path,
  timeout: float,
  user_agent: str,
  retries:  int,
  backoff: float,
) -> None:
  last_exc:  Exception | None = None
  for attempt in range(retries + 1):
    try:
      download_to_path(opener=opener, url=url, dest=dest, timeout=timeout, user_agent=user_agent)
      return
    except (HTTPError, URLError, TimeoutError, OSError) as e:
      last_exc = e
      if attempt < retries:
        time. sleep(backoff * (2 ** attempt))
  if last_exc: 
    raise last_exc
  raise RuntimeError("download failed")


def main(argv: list[str]) -> int:
  ns = parse_args(argv)
  json_path_s = dequote_dragdrop(ns.json_path)
  out_dir_s = dequote_dragdrop(ns.out_dir)
  json_path:  Path | None = None
  out_dir: Path | None = None
  if json_path_s: 
    json_path = Path(json_path_s)
  elif not ns.no_tui: 
    json_path = tui_select_path(title="Select memories_history.json", start=Path.cwd(), mode="file")
  if out_dir_s: 
    out_dir = Path(out_dir_s)
  elif not ns.no_tui:
    out_dir = tui_select_path(title="Select output directory", start=Path.cwd(), mode="dir")
  if json_path is None: 
    die("Missing --json (or enable TUI by omitting --no-tui).")
  if out_dir is None: 
    die("Missing --out (or enable TUI by omitting --no-tui).")
  json_path, out_dir = json_path.expanduser(), out_dir.expanduser()
  if not json_path.is_file():
    die(f"JSON file does not exist: {json_path}")
  out_dir. mkdir(parents=True, exist_ok=True)
  items = load_items(json_path, ns.media_type)
  if not items:
    print("No media items found.")
    return 0
  existing = {p.name for p in out_dir.iterdir() if p.is_file()}
  opener = build_opener()
  ok, skipped, failed = 0, 0, 0
  for it in items:
    try:
      filename = build_filename(it.date_str, it.ext, existing)
    except ValueError as e: 
      failed += 1
      print(f"FAIL bad date '{it.date_str}': {e}", file=sys.stderr)
      continue
    dest = out_dir / filename
    if ns.skip_existing and dest.exists():
      skipped += 1
      continue
    if ns.dry_run:
      print(f"DRY {dest. name} <- {it.url}")
      ok += 1
      continue
    print(f"GET  {dest.name}")
    try:
      download_with_retries(
        opener=opener, url=it.url, dest=dest, timeout=ns.timeout,
        user_agent=ns.user_agent, retries=ns.retries, backoff=ns. retry_backoff,
      )
      existing.add(dest.name)
      ok += 1
    except (HTTPError, URLError, TimeoutError, OSError) as e:
      failed += 1
      print(f"FAIL {dest.name}:  {e}", file=sys.stderr)
  print(f"Done.  ok={ok} skipped={skipped} failed={failed}")
  return 0 if failed == 0 else 2


if __name__ == "__main__": 
  raise SystemExit(main(sys.argv[1:]))
