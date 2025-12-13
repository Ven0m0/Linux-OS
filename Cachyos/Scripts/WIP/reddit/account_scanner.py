#!/usr/bin/env python3
"""Multi-source account scanner: Reddit toxicity + Sherlock OSINT."""
import argparse
import asyncio
import csv
import shutil
import sys
import time
from pathlib import Path

import httpx
import orjson
import praw
import uvloop

# Perspective API constants
PERSPECTIVE_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
DEFAULT_TIMEOUT = 10
ATTRIBUTES = ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]


def get_limiter(rate_per_min):
    """Closure-based rate limiter."""
    delay = 60.0 / rate_per_min
    last_call = [0.0]

    async def wait():
        now = time.monotonic()
        elapsed = now - last_call[0]
        if elapsed < delay:
            await asyncio.sleep(delay - elapsed)
        last_call[0] = time.monotonic()

    return wait


async def run_sherlock(username, timeout, verbose):
    """Run Sherlock username search via subprocess."""
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

        with open(tmp_output, "rb") as f:
            data = orjson.loads(f.read())

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
    except Exception as e:
        if verbose:
            print(f"Sherlock error: {e}", file=sys.stderr)
        return []


async def check_toxicity(client, text, key, limiter):
    """Analyze text toxicity via Perspective API using orjson."""
    if not text.strip():
        return {}

    await limiter()

    payload = {
        "comment": {"text": text},
        "languages": ["en"],
        "requestedAttributes": {a: {} for a in ATTRIBUTES},
    }

    try:
        # manual serialization with orjson is faster
        resp = await client.post(
            PERSPECTIVE_URL,
            params={"key": key},
            content=orjson.dumps(payload),
            headers={"Content-Type": "application/json"},
            timeout=10,
        )

        if resp.status_code == 200:
            data = orjson.loads(resp.content)
            return {
                k: v["summaryScore"]["value"] for k, v in data.get("attributeScores", {}).items()
            }
        return {}
    except Exception:
        return {}


async def scan_reddit(args):
    """Fetch and analyze Reddit content."""
    limiter = get_limiter(args.rate_per_min)
    print(f"🤖 Reddit: Fetching content for u/{args.username}...")

    try:
        reddit = praw.Reddit(
            client_id=args.client_id,
            client_secret=args.client_secret,
            user_agent=args.user_agent,
        )
        user = reddit.redditor(args.username)

        items = []
        # Gather comments
        items.extend(
            [
                ("comment", c.subreddit.display_name, c.body, c.created_utc)
                for c in user.comments.new(limit=args.comments)
            ]
        )
        # Gather posts
        items.extend(
            [
                ("post", s.subreddit.display_name, f"{s.title}\n{s.selftext}", s.created_utc)
                for s in user.submissions.new(limit=args.posts)
            ]
        )
    except Exception as e:
        print(f"Reddit API Error: {e}", file=sys.stderr)
        return

    print(f"🤖 Reddit: Analyzing {len(items)} items...")

    async with httpx.AsyncClient() as client:
        tasks = [check_toxicity(client, text, args.api_key, limiter) for _, _, text, _ in items]
        results = await asyncio.gather(*tasks)

    flagged = []
    for (kind, sub, text, ts), scores in zip(items, results):
        if any(s >= args.threshold for s in scores.values()):
            flagged.append(
                {
                    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)),
                    "type": kind,
                    "subreddit": str(sub),
                    "content": text[:500],  # Truncate for CSV
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


async def main_async():
    p = argparse.ArgumentParser()
    p.add_argument("username")
    p.add_argument("--mode", choices=["sherlock", "reddit", "both"], default="both")

    # Auth
    p.add_argument("--perspective-api-key", dest="api_key")
    p.add_argument("--client-id")
    p.add_argument("--client-secret")
    p.add_argument("--user-agent")

    # Config
    p.add_argument("--comments", type=int, default=50)
    p.add_argument("--posts", type=int, default=20)
    p.add_argument("--toxicity-threshold", dest="threshold", type=float, default=0.7)
    p.add_argument("--rate-per-min", type=float, default=60.0)
    p.add_argument("--sherlock-timeout", type=int, default=60)

    # Output
    p.add_argument("--output-reddit", default="reddit_flagged.csv")
    p.add_argument("--output-sherlock", default="sherlock_results.json")
    p.add_argument("--verbose", action="store_true")

    args = p.parse_args()

    tasks = []

    if args.mode in ["sherlock", "both"]:
        if shutil.which("sherlock"):
            tasks.append(run_sherlock(args.username, args.sherlock_timeout, args.verbose))
        else:
            print("Sherlock not installed, skipping.")

    if args.mode in ["reddit", "both"]:
        if all([args.api_key, args.client_id, args.client_secret, args.user_agent]):
            tasks.append(scan_reddit(args))
        elif args.mode == "reddit":
            sys.exit("Error: Reddit mode requires API keys.")

    results = await asyncio.gather(*tasks)

    # Handle Sherlock results (first result if sherlock ran)
    sherlock_data = next((r for r in results if isinstance(r, list)), None)
    if sherlock_data:
        with open(args.output_sherlock, "wb") as f:
            f.write(orjson.dumps(sherlock_data, option=orjson.OPT_INDENT_2))
        print(f"🔎 Sherlock: Found {len(sherlock_data)} accounts → {args.output_sherlock}")


def main():
    uvloop.install()
    asyncio.run(main_async())


if __name__ == "__main__":
    main()
