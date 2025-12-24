#!/usr/bin/env python3
"""
Snapchat memories_history.json downloader.

- Zero external deps (stdlib only)
- CLI flags first; optional interactive TUI selection fallback
- Downloads "Saved Media" items by "Media Download Url"
- Filename based on UTC timestamp; collision-safe

Run:
  python3 -OO import_json.py --json /path/memories_history.json --out /path/out
Or interactive:
  python3 -OO import_json.py
"""

from __future__ import annotations

import argparse
import curses
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


DATE_FMT = "%Y-%m-%d %H:%M:%S UTC"


@dataclass(frozen=True, slots=True)
class Item:
  date_str: str
  url: str
  ext: str


def die(msg: str, code: int = 1) -> None:
  print(msg, file=sys.stderr)
  raise SystemExit(code)


def dequote_dragdrop(s: str) -> str:
  s = s.strip()
  if len(s) >= 2 and ((s[0] == s[-1] == '"') or (s[0] == s[-1] == "'")):
    return s[1:-1]
  return s


def parse_args(argv: list[str]) -> argparse.Namespace:
  p = argparse.ArgumentParser(
    prog="import_json.py",
    description="Download Snapchat Saved Media from memories_history.json (stdlib only).",
  )
  p.add_argument("--json", dest="json_path", default="", help="Path to memories_history.json")
  p.add_argument("--out", dest="out_dir", default="", help="Output directory for downloads")
  p.add_argument("--type", dest="media_type", default="all", choices=["all", "video", "image"],
                 help="Filter media type")
  p.add_argument("--dry-run", action="store_true", help="List what would be downloaded")
  p.add_argument("--skip-existing", action="store_true", help="Skip if target file already exists")
  p.add_argument("--timeout", type=float, default=30.0, help="HTTP timeout seconds (default: 30)")
  p.add_argument("--retries", type=int, default=3, help="Retries per file (default: 3)")
  p.add_argument("--retry-backoff", type=float, default=1.0,
                 help="Seconds base backoff between retries (default: 1.0)")
  p.add_argument("--user-agent", default="Mozilla/5.0 (SnapchatMemoryDownloader; +stdlib)",
                 help="User-Agent header")
  p.add_argument("--no-tui", action="store_true", help="Disable TUI prompts; require flags")
  return p.parse_args(argv)


def load_items(json_path: Path, media_type: str) -> list[Item]:
  try:
    raw = json_path.read_text(encoding="utf-8")
  except OSError as e:
    die(f"Failed to read JSON file: {json_path}\n{e}")

  try:
    data = json.loads(raw)
  except json.JSONDecodeError as e:
    die(f"Invalid JSON: {json_path}\n{e}")

  media_items = data.get("Saved Media", [])
  if not isinstance(media_items, list):
    die('JSON does not contain expected list at key "Saved Media"')

  out: list[Item] = []
  for obj in media_items:
    if not isinstance(obj, dict):
      continue

    mt = str(obj.get("Media Type", "")).lower()
    is_video = mt == "video"
    ext = ".mp4" if is_video else ".jpg"

    if media_type == "video" and not is_video:
      continue
    if media_type == "image" and is_video:
      continue

    date_str = obj.get("Date")
    url = obj.get("Media Download Url")
    if not isinstance(date_str, str) or not date_str.strip():
      continue
    if not isinstance(url, str) or not url.strip():
      continue

    out.append(Item(date_str=date_str, url=url, ext=ext))

  return out


def build_filename(date_str: str, ext: str, existing: set[str]) -> str:
  dt = datetime.strptime(date_str, DATE_FMT)
  base = dt.strftime("%Y-%m-%d_%H-%M-%S")
  filename = f"{base}{ext}"
  n = 1
  while filename in existing:
    filename = f"{base}_{n}{ext}"
    n += 1
  return filename


def atomic_download(url: str, dest: Path, timeout: float, user_agent: str) -> None:
  tmp = dest.with_suffix(dest.suffix + ".part")
  req = urllib.request.Request(url, headers={"User-Agent": user_agent})
  with urllib.request.urlopen(req, timeout=timeout) as r:
    with open(tmp, "wb") as f:
      while True:
        chunk = r.read(1024 * 256)
        if not chunk:
          break
        f.write(chunk)
  os.replace(tmp, dest)


def download_with_retries(
  *,
  url: str,
  dest: Path,
  timeout: float,
  user_agent: str,
  retries: int,
  backoff: float,
) -> None:
  last: Exception | None = None
  for attempt in range(retries + 1):
    try:
      atomic_download(url, dest, timeout, user_agent)
      return
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
      last = e
      if attempt >= retries:
        break
      time.sleep(backoff * (2 ** attempt))
  raise last if last else RuntimeError("download failed")


def list_dir_entries(dirpath: Path) -> list[Path]:
  try:
    entries = list(dirpath.iterdir())
  except OSError:
    return []
  entries = [p for p in entries if not p.name.startswith(".")]
  entries.sort(key=lambda p: (not p.is_dir(), p.name.lower()))
  return entries


def tui_select_path(
  *,
  title: str,
  start: Path,
  mode: str,  # "file" or "dir"
  file_re: re.Pattern[str] | None = None,
) -> Path:
  if not sys.stdin.isatty() or not sys.stdout.isatty():
    die("TUI requires a TTY. Provide --json/--out or use --no-tui.")

  if mode not in ("file", "dir"):
    raise ValueError("mode must be file or dir")

  start = start.expanduser().resolve()
  if not start.exists():
    start = Path.cwd()

  def run(stdscr: "curses._CursesWindow") -> Path:
    curses.curs_set(0)
    stdscr.keypad(True)

    cwd = start
    idx = 0
    while True:
      entries = list_dir_entries(cwd)
      shown: list[Path] = [cwd.parent] + entries  # first entry = ".."
      if idx >= len(shown):
        idx = max(0, len(shown) - 1)

      stdscr.erase()
      h, w = stdscr.getmaxyx()

      header = f"{title}  [{mode}]  cwd: {cwd}"
      stdscr.addnstr(0, 0, header, w - 1)
      help1 = "Arrows/j/k: move  Enter: open/select  Backspace: up  q: quit"
      stdscr.addnstr(1, 0, help1, w - 1)

      row0 = 3
      max_rows = max(1, h - row0 - 1)
      top = 0
      if idx >= max_rows:
        top = idx - max_rows + 1

      for i in range(top, min(len(shown), top + max_rows)):
        p = shown[i]
        name = ".." if i == 0 else p.name + ("/" if p.is_dir() else "")
        if i == idx:
          stdscr.attron(curses.A_REVERSE)
        stdscr.addnstr(row0 + (i - top), 0, name, w - 1)
        if i == idx:
          stdscr.attroff(curses.A_REVERSE)

      stdscr.refresh()
      k = stdscr.getch()

      if k in (ord("q"), 27):  # q or ESC
        raise KeyboardInterrupt

      if k in (curses.KEY_UP, ord("k")):
        idx = max(0, idx - 1)
        continue
      if k in (curses.KEY_DOWN, ord("j")):
        idx = min(len(shown) - 1, idx + 1)
        continue

      if k in (curses.KEY_BACKSPACE, 127, 8):
        cwd = cwd.parent
        idx = 0
        continue

      if k in (curses.KEY_ENTER, 10, 13):
        pick = shown[idx]
        if idx == 0:
          cwd = cwd.parent
          idx = 0
          continue

        if pick.is_dir():
          if mode == "dir":
            return pick
          cwd = pick
          idx = 0
          continue

        # file
        if mode == "file":
          if file_re and not file_re.search(pick.name):
            continue
          return pick

  try:
    return curses.wrapper(run)
  except KeyboardInterrupt:
    die("Aborted.")


def main(argv: list[str]) -> int:
  ns = parse_args(argv)

  json_path_s = dequote_dragdrop(ns.json_path)
  out_dir_s = dequote_dragdrop(ns.out_dir)

  if not json_path_s and not ns.no_tui:
    json_path = tui_select_path(
      title="Select Snapchat memories_history.json",
      start=Path.cwd(),
      mode="file",
      file_re=re.compile(r"memories_history\.json$", re.I),
    )
  else:
    json_path = Path(json_path_s) if json_path_s else Path()

  if not out_dir_s and not ns.no_tui:
    out_dir = tui_select_path(
      title="Select output directory",
      start=Path.cwd(),
      mode="dir",
    )
  else:
    out_dir = Path(out_dir_s) if out_dir_s else Path()

  if not json_path:
    die("Missing --json (or enable TUI by omitting --no-tui).")
  if not out_dir:
    die("Missing --out (or enable TUI by omitting --no-tui).")

  json_path = json_path.expanduser()
  out_dir = out_dir.expanduser()

  if not json_path.is_file():
    die(f"JSON file does not exist: {json_path}")
  out_dir.mkdir(parents=True, exist_ok=True)

  items = load_items(json_path, ns.media_type)
  if not items:
    print("No media items found.")
    return 0

  existing = {p.name for p in out_dir.iterdir() if p.is_file()}

  ok = 0
  skipped = 0
  failed = 0

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
      print(f"DRY {dest.name} <- {it.url}")
      ok += 1
      continue

    print(f"GET  {dest.name}")
    try:
      download_with_retries(
        url=it.url,
        dest=dest,
        timeout=ns.timeout,
        user_agent=ns.user_agent,
        retries=ns.retries,
        backoff=ns.retry_backoff,
      )
      existing.add(dest.name)
      ok += 1
    except Exception as e:
      failed += 1
      print(f"FAIL {dest.name}: {e}", file=sys.stderr)

  print(f"Done. ok={ok} skipped={skipped} failed={failed}")
  return 0 if failed == 0 else 2


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
