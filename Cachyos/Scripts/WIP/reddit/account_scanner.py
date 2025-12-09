#!/usr/bin/env python3
"""Multi-source account scanner: Reddit toxicity + Sherlock OSINT.

Scans Reddit user content for toxicity via Perspective API and/or
discovers username presence across platforms via Sherlock.

Arch deps: python-praw python-pandas python-httpx sherlock-git
Debian: uv pip install praw pandas httpx orjson sherlock-project
"""

from __future__ import annotations
import argparse
import asyncio
import json
import shutil
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, TypedDict

try:
    import orjson as fast_json

    JSON_LOADS = lambda x: fast_json.loads(x)
    JSON_DUMPS = lambda x: fast_json.dumps(x).decode()
except ImportError:
    JSON_LOADS = json.loads
    JSON_DUMPS = json.dumps

import pandas as pd

# Perspective API constants
PERSPECTIVE_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
DEFAULT_TIMEOUT = 10
DEFAULT_RATE_PER_MIN = 60.0
DEFAULT_MAX_RETRIES = 5
DEFAULT_BACKOFF_BASE = 1.0
ATTRIBUTES = ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]

ScannerMode = Literal["sherlock", "reddit", "both"]


class PerspectiveScore(TypedDict, total=False):
    """Perspective API score response."""

    TOXICITY: float
    INSULT: float
    PROFANITY: float
    SEXUALLY_EXPLICIT: float


class FlaggedItem(TypedDict):
    """Flagged Reddit content record."""

    timestamp: str
    type: str
    subreddit: str
    content: str
    TOXICITY: float
    INSULT: float
    PROFANITY: float
    SEXUALLY_EXPLICIT: float


class SherlockResult(TypedDict):
    """Sherlock platform discovery result."""

    platform: str
    url: str
    status: str
    response_time: float


@dataclass
class RateLimiter:
    """Simple token bucket rate limiter."""

    min_interval: float
    last_call: float = field(default_factory=time.monotonic)

    async def acquire(self) -> None:
        """Wait until next request is allowed."""
        elapsed = time.monotonic() - self.last_call
        if elapsed < self.min_interval:
            await asyncio.sleep(self.min_interval - elapsed)
        self.last_call = time.monotonic()


@dataclass
class Config:
    """Scanner configuration."""

    username: str
    mode: ScannerMode
    api_key: str = ""
    client_id: str = ""
    client_secret: str = ""
    user_agent: str = ""
    num_comments: int = 50
    num_posts: int = 20
    threshold: float = 0.7
    output_reddit: Path = Path("reddit_flagged.csv")
    output_sherlock: Path = Path("sherlock_results.json")
    rate_per_min: float = DEFAULT_RATE_PER_MIN
    max_retries: int = DEFAULT_MAX_RETRIES
    timeout: int = DEFAULT_TIMEOUT
    sherlock_timeout: int = 60
    verbose: bool = False

    def validate(self) -> None:
        """Validate configuration values."""
        if self.mode in ("reddit", "both"):
            if not (0.0 <= self.threshold <= 1.0):
                raise ValueError("threshold must be in [0.0, 1.0]")
            if not self.api_key.strip():
                raise ValueError("perspective_api_key required for reddit mode")
            if not self.client_id.strip():
                raise ValueError("client_id required for reddit mode")
            if not self.client_secret.strip():
                raise ValueError("client_secret required for reddit mode")
            if not self.user_agent.strip():
                raise ValueError("user_agent required for reddit mode")

        if self.mode in ("sherlock", "both"):
            if not shutil.which("sherlock"):
                raise FileNotFoundError(
                    "sherlock not found. Install: pacman -S sherlock-git or pip install sherlock-project"
                )


def parse_args() -> Config:
    """Parse and validate CLI arguments."""
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("username", help="Target username (without u/ or @)")
    p.add_argument(
        "--mode",
        choices=["sherlock", "reddit", "both"],
        default="both",
        help="Scanner mode (default: both)",
    )

    # Reddit options
    reddit_g = p.add_argument_group("Reddit scanner options")
    reddit_g.add_argument("--comments", type=int, default=50, help="Num comments to fetch")
    reddit_g.add_argument("--posts", type=int, default=20, help="Num posts to fetch")
    reddit_g.add_argument(
        "--toxicity-threshold",
        type=float,
        default=0.7,
        help="Toxicity flag threshold (0.0-1.0)",
    )
    reddit_g.add_argument("--perspective-api-key", default="", help="Perspective API key")
    reddit_g.add_argument("--client-id", default="", help="Reddit client_id")
    reddit_g.add_argument("--client-secret", default="", help="Reddit client_secret")
    reddit_g.add_argument("--user-agent", default="", help="Reddit user_agent")
    reddit_g.add_argument(
        "--output-reddit",
        default="reddit_flagged.csv",
        help="Reddit output CSV",
    )
    reddit_g.add_argument(
        "--rate-per-min",
        type=float,
        default=DEFAULT_RATE_PER_MIN,
        help="Max Perspective req/min",
    )
    reddit_g.add_argument("--max-retries", type=int, default=5, help="Max API retries")

    # Sherlock options
    sherlock_g = p.add_argument_group("Sherlock scanner options")
    sherlock_g.add_argument(
        "--output-sherlock",
        default="sherlock_results.json",
        help="Sherlock output JSON",
    )
    sherlock_g.add_argument(
        "--sherlock-timeout",
        type=int,
        default=60,
        help="Sherlock timeout per site (seconds)",
    )

    p.add_argument("--verbose", action="store_true", help="Verbose output")

    args = p.parse_args()

    cfg = Config(
        username=args.username,
        mode=args.mode,
        api_key=args.perspective_api_key,
        client_id=args.client_id,
        client_secret=args.client_secret,
        user_agent=args.user_agent,
        num_comments=args.comments,
        num_posts=args.posts,
        threshold=args.toxicity_threshold,
        output_reddit=Path(args.output_reddit),
        output_sherlock=Path(args.output_sherlock),
        rate_per_min=args.rate_per_min,
        max_retries=args.max_retries,
        sherlock_timeout=args.sherlock_timeout,
        verbose=args.verbose,
    )
    cfg.validate()
    return cfg


async def run_sherlock(username: str, cfg: Config) -> list[SherlockResult]:
    """Run Sherlock username search across platforms.

    Args:
        username: Username to search
        cfg: Scanner config

    Returns:
        List of platform results
    """
    print(f"Running Sherlock for '{username}'...")
    tmp_output = Path(f"/tmp/sherlock_{username}_{int(time.time())}.json")

    cmd = [
        "sherlock",
        username,
        "--json",
        tmp_output.as_posix(),
        "--timeout",
        str(cfg.sherlock_timeout),
        "--print-found",
    ]

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()

        if cfg.verbose and stderr:
            sys.stderr.write(stderr.decode())

        if proc.returncode != 0:
            print(f"Sherlock exit {proc.returncode}", file=sys.stderr)
            return []

        if not tmp_output.exists():
            print("Sherlock output not found", file=sys.stderr)
            return []

        with tmp_output.open("rb") as f:
            raw_data = JSON_LOADS(f.read())

        results: list[SherlockResult] = []
        for platform, data in raw_data.items():
            if isinstance(data, dict) and data.get("status") == "Claimed":
                results.append(
                    SherlockResult(
                        platform=platform,
                        url=data.get("url_user", ""),
                        status=data["status"],
                        response_time=data.get("response_time_s", 0.0),
                    )
                )

        tmp_output.unlink(missing_ok=True)
        return results

    except Exception as e:
        print(f"Sherlock error: {e}", file=sys.stderr)
        tmp_output.unlink(missing_ok=True)
        return []


async def check_toxicity(text: str, client, cfg: Config, limiter: RateLimiter) -> PerspectiveScore:
    """Analyze text toxicity via Perspective API.

    Args:
        text: Content to analyze
        client: Async HTTP client
        cfg: Scanner config
        limiter: Rate limiter

    Returns:
        Dict of attribute scores
    """
    if not text.strip():
        return {}

    await limiter.acquire()

    payload = {
        "comment": {"text": text},
        "languages": ["en"],
        "requestedAttributes": {a: {} for a in ATTRIBUTES},
    }

    for attempt in range(1, cfg.max_retries + 1):
        try:
            resp = await client.post(
                PERSPECTIVE_URL,
                params={"key": cfg.api_key},
                json=payload,
                timeout=cfg.timeout,
            )
            resp.raise_for_status()
            result = JSON_LOADS(resp.content)
            return {k: v["summaryScore"]["value"] for k, v in result.get("attributeScores", {}).items()}
        except Exception as e:
            # Handle httpx errors
            error_type = type(e).__name__
            if "429" in str(e) or "HTTPStatusError" in error_type:
                backoff = DEFAULT_BACKOFF_BASE * (2 ** (attempt - 1))
                if cfg.verbose:
                    print(
                        f"429 backoff {backoff:.1f}s ({attempt}/{cfg.max_retries})",
                        file=sys.stderr,
                    )
                await asyncio.sleep(backoff)
                continue
            if cfg.verbose:
                print(f"Error: {e}", file=sys.stderr)
            await asyncio.sleep(2 ** (attempt - 1))
            if attempt == cfg.max_retries:
                return {}

    return {}


async def analyze_reddit_content(items: list[tuple[str, str, str, float]], cfg: Config) -> list[FlaggedItem]:
    """Analyze list of Reddit content items concurrently.

    Args:
        items: List of (type, subreddit, text, timestamp) tuples
        cfg: Scanner config

    Returns:
        List of flagged items
    """
    try:
        import httpx
    except ImportError:
        print("httpx required: pacman -S python-httpx", file=sys.stderr)
        sys.exit(1)

    limiter = RateLimiter(60.0 / cfg.rate_per_min)
    flagged: list[FlaggedItem] = []

    async with httpx.AsyncClient() as client:
        tasks = [check_toxicity(text, client, cfg, limiter) for _, _, text, _ in items]
        scores_list = await asyncio.gather(*tasks)

    for (item_type, sub, text, ts), scores in zip(items, scores_list):
        if any(s >= cfg.threshold for s in scores.values()):
            flagged.append(
                FlaggedItem(
                    timestamp=time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)),
                    type=item_type,
                    subreddit=sub,
                    content=text,
                    **scores,  # type: ignore
                )
            )
    return flagged


def fetch_reddit_content(username: str, cfg: Config) -> list[tuple[str, str, str, float]]:
    """Fetch user comments and posts from Reddit.

    Args:
        username: Reddit username
        cfg: Scanner config

    Returns:
        List of (type, subreddit, text, timestamp) tuples
    """
    try:
        import praw
    except ImportError:
        print("praw required: pacman -S python-praw", file=sys.stderr)
        sys.exit(1)

    reddit = praw.Reddit(
        client_id=cfg.client_id,
        client_secret=cfg.client_secret,
        user_agent=cfg.user_agent,
    )

    items: list[tuple[str, str, str, float]] = []
    user = reddit.redditor(username)

    print(f"Fetching {cfg.num_comments} comments...")
    for comment in user.comments.new(limit=cfg.num_comments):
        items.append(
            (
                "comment",
                str(comment.subreddit),
                comment.body or "",
                comment.created_utc,
            )
        )

    print(f"Fetching {cfg.num_posts} posts...")
    for post in user.submissions.new(limit=cfg.num_posts):
        text = f"{post.title}\n{post.selftext}".strip()
        items.append(("post", str(post.subreddit), text, post.created_utc))

    return items


def save_reddit_results(flagged: list[FlaggedItem], path: Path) -> None:
    """Save flagged Reddit items to CSV.

    Args:
        flagged: List of flagged content
        path: Output CSV path
    """
    if not flagged:
        print("No flagged Reddit content.")
        return

    df = pd.DataFrame(flagged)
    df.to_csv(path, index=False)
    print(f"Flagged {len(flagged)} Reddit items → {path}")


def save_sherlock_results(results: list[SherlockResult], path: Path) -> None:
    """Save Sherlock results to JSON.

    Args:
        results: List of platform results
        path: Output JSON path
    """
    if not results:
        print("No Sherlock matches found.")
        return

    with path.open("w") as f:
        f.write(JSON_DUMPS(results))
    print(f"Found {len(results)} platforms → {path}")

    if results:
        print("\nPlatforms found:")
        for r in sorted(results, key=lambda x: x["platform"]):
            print(f"  {r['platform']:20s} {r['url']}")


async def run_reddit_scanner(cfg: Config) -> None:
    """Run Reddit toxicity scanner."""
    print("\n=== Reddit Scanner ===")
    items = fetch_reddit_content(cfg.username, cfg)
    print(f"Analyzing {len(items)} items...")
    flagged = await analyze_reddit_content(items, cfg)
    save_reddit_results(flagged, cfg.output_reddit)


async def run_sherlock_scanner(cfg: Config) -> None:
    """Run Sherlock platform scanner."""
    print("\n=== Sherlock Scanner ===")
    results = await run_sherlock(cfg.username, cfg)
    save_sherlock_results(results, cfg.output_sherlock)


async def main_async() -> None:
    """Main async entry point."""
    cfg = parse_args()

    try:
        if cfg.mode == "sherlock":
            await run_sherlock_scanner(cfg)
        elif cfg.mode == "reddit":
            await run_reddit_scanner(cfg)
        else:  # both
            await asyncio.gather(run_sherlock_scanner(cfg), run_reddit_scanner(cfg))

        print("\nScan complete.")

    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        if cfg.verbose:
            import traceback

            traceback.print_exc()
        sys.exit(1)


def main() -> None:
    """Synchronous entry point."""
    asyncio.run(main_async())


if __name__ == "__main__":
    main()
