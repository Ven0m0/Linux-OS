#!/usr/bin/env python3
"""Multi-source account scanner: Reddit toxicity + Sherlock OSINT (async)."""
import argparse
import asyncio
import csv
import shutil
import sys
import time
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple
import httpx
import orjson
import uvloop
from asyncpraw import Reddit
from asyncprawcore import AsyncPrawcoreException

PERSPECTIVE_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
DEFAULT_TIMEOUT = 10
ATTRIBUTES = ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]

def get_limiter(rate_per_min: float):
    delay = 60.0 / rate_per_min
    last_call = [0.0]

    async def wait():
        now = time.monotonic()
        elapsed = now - last_call[0]
        if elapsed < delay:
            await asyncio.sleep(delay - elapsed)
        last_call[0] = time.monotonic()

    return wait

def sherlock_available() -> bool:
    return shutil.which("sherlock") is not None

async def run_sherlock(
    username: str, timeout: int, verbose: bool
) -> List[Dict[str, object]]:
    print(f"🔎 Sherlock: Scanning '{username}'...")
    tmp_output = Path(f"/tmp/sherlock_{username}_{int(time.time())}.json")
    cmd = [
        "sherlock",
        username,
        "--json",
        str(tmp_output),
        "--timeout",
        str(timeout),
        "--print-found",
    ]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        await proc.communicate()
        if not tmp_output.exists():
            return []
        data = orjson.loads(tmp_output.read_bytes())
        tmp_output.unlink(missing_ok=True)
        return [
            {
                "platform": k,
                "url": d.get("url_user"),
                "status": d.get("status"),
                "response_time": d.get("response_time_s"),
            }
            for k, d in data.items()
            if d.get("status") == "Claimed"
        ]
    except Exception as e:  # pragma: no cover - external binary
        if verbose:
            print(f"Sherlock error: {e}", file=sys.stderr)
        return []

async def check_toxicity(
    client: httpx.AsyncClient, text: str, key: str, limiter
) -> Dict[str, float]:
    if not text.strip():
        return {}
    await limiter()
    payload = {
        "comment": {"text": text},
        "languages": ["en"],
        "requestedAttributes": {a: {} for a in ATTRIBUTES},
    }
    try:
        resp = await client.post(
            PERSPECTIVE_URL,
            params={"key": key},
            content=orjson.dumps(payload),
            headers={"Content-Type": "application/json"},
            timeout=DEFAULT_TIMEOUT,
        )
        if resp.status_code == 200:
            data = orjson.loads(resp.content)
            return {
                k: v["summaryScore"]["value"]
                for k, v in data.get("attributeScores", {}).items()
            }
    except Exception:
        return {}
    return {}

async def fetch_reddit_items(
    args: argparse.Namespace,
) -> Tuple[Optional[List[Tuple[str, str, str, float]]], Optional[Iterable]]:
    limiter = get_limiter(args.rate_per_min)
    print(f"🤖 Reddit: Fetching content for u/{args.username}...")
    try:
        reddit = Reddit(
            client_id=args.client_id,
            client_secret=args.client_secret,
            user_agent=args.user_agent,
            requestor_kwargs={"request_timeout": DEFAULT_TIMEOUT},
        )
    except Exception as e:
        print(f"Reddit init error: {e}", file=sys.stderr)
        return None, None
    user = reddit.redditor(args.username)
    items: List[Tuple[str, str, str, float]] = []
    try:
        async for c in user.comments.new(limit=args.comments):
            items.append(("comment", c.subreddit.display_name, c.body, c.created_utc))
        async for s in user.submissions.new(limit=args.posts):
            items.append(
                (
                    "post",
                    s.subreddit.display_name,
                    f"{s.title}\n{s.selftext}",
                    s.created_utc,
                )
            )
    except AsyncPrawcoreException as e:
        print(f"Reddit API Error: {e}", file=sys.stderr)
        await reddit.close()
        return None, None
    await reddit.close()
    if not items:
        print("🤖 Reddit: No items to analyze.")
        return None, None
    return items, limiter

async def scan_reddit(args: argparse.Namespace) -> Optional[List[Dict[str, object]]]:
    items, limiter = await fetch_reddit_items(args)
    if not items:
        return None
    print(f"🤖 Reddit: Analyzing {len(items)} items...")
    limits = httpx.Limits(max_keepalive_connections=5, max_connections=10)
    async with httpx.AsyncClient(http2=True, limits=limits) as client:
        results = await asyncio.gather(
            *[
                check_toxicity(client, text, args.api_key, limiter)
                for _, _, text, _ in items
            ]
        )
    flagged: List[Dict[str, object]] = []
    for (kind, sub, text, ts), scores in zip(items, results):
        if any(s >= args.threshold for s in scores.values()):
            flagged.append(
                {
                    "timestamp": time.strftime(
                        "%Y-%m-%d %H:%M:%S", time.localtime(ts)
                    ),
                    "type": kind,
                    "subreddit": str(sub),
                    "content": text[:500],
                    **scores,
                }
            )
    if flagged:
        with open(args.output_reddit, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(
                f, fieldnames=["timestamp", "type", "subreddit", "content"] + ATTRIBUTES
            )
            writer.writeheader()
            writer.writerows(flagged)
        print(f"🤖 Reddit: Saved {len(flagged)} flagged items → {args.output_reddit}")
    else:
        print("🤖 Reddit: No toxic content found.")
    return flagged

async def main_async() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("username")
    parser.add_argument("--mode", choices=["sherlock", "reddit", "both"], default="both")
    parser.add_argument("--perspective-api-key", dest="api_key")
    parser.add_argument("--client-id")
    parser.add_argument("--client-secret")
    parser.add_argument("--user-agent")
    parser.add_argument("--comments", type=int, default=50)
    parser.add_argument("--posts", type=int, default=20)
    parser.add_argument(
        "--toxicity-threshold", dest="threshold", type=float, default=0.7
    )
    parser.add_argument("--rate-per-min", type=float, default=60.0)
    parser.add_argument("--sherlock-timeout", type=int, default=60)
    parser.add_argument("--output-reddit", default="reddit_flagged.csv")
    parser.add_argument("--output-sherlock", default="sherlock_results.json")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    tasks = []
    if args.mode in ["sherlock", "both"]:
        if sherlock_available():
            tasks.append(
                run_sherlock(args.username, args.sherlock_timeout, args.verbose)
            )
        else:
            print("Sherlock not installed, skipping.")
    if args.mode in ["reddit", "both"]:
        if all([args.api_key, args.client_id, args.client_secret, args.user_agent]):
            tasks.append(scan_reddit(args))
        elif args.mode == "reddit":
            sys.exit("Error: Reddit mode requires API keys.")
    results = await asyncio.gather(*tasks) if tasks else []
    sherlock_data = next((r for r in results if isinstance(r, list)), None)
    if sherlock_data:
        with open(args.output_sherlock, "wb") as f:
            f.write(orjson.dumps(sherlock_data, option=orjson.OPT_INDENT_2))
        print(
            f"🔎 Sherlock: Found {len(sherlock_data)} accounts → {args.output_sherlock}"
        )

def main() -> None:
    uvloop.install()
    asyncio.run(main_async())

if __name__ == "__main__":
    main()
