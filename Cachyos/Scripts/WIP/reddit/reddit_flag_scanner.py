#!/usr/bin/env python3
"""Reddit account content toxicity scanner using Perspective API. 

Scans Reddit user comments/posts for toxic content using Google's
Perspective API. Supports async concurrent requests with rate limiting. 

Arch deps: python-praw python-pandas python-httpx
Debian: uv pip install praw pandas httpx orjson
"""

from __future__ import annotations
import argparse
import asyncio
import json
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, TypedDict

try:
    import orjson as fast_json
    JSON_LOADS = lambda x: fast_json.loads(x)
    JSON_DUMPS = lambda x: fast_json.dumps(x). decode()
except ImportError:
    JSON_LOADS = json.loads
    JSON_DUMPS = json.dumps

import pandas as pd
import praw

try:
    import httpx
except ImportError:
    print("httpx required: pacman -S python-httpx", file=sys.stderr)
    sys.exit(1)

# Constants
PERSPECTIVE_URL = (
    "https://commentanalyzer.googleapis.com/v1alpha1/"
    "comments:analyze"
)
DEFAULT_TIMEOUT = 10
DEFAULT_RATE_PER_MIN = 60. 0
DEFAULT_MAX_RETRIES = 5
DEFAULT_BACKOFF_BASE = 1.0
ATTRIBUTES = ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]


class PerspectiveScore(TypedDict, total=False):
    """Perspective API score response."""
    TOXICITY: float
    INSULT: float
    PROFANITY: float
    SEXUALLY_EXPLICIT: float


class FlaggedItem(TypedDict):
    """Flagged content record."""
    timestamp: str
    type: str
    subreddit: str
    content: str
    TOXICITY: float
    INSULT: float
    PROFANITY: float
    SEXUALLY_EXPLICIT: float


@dataclass
class RateLimiter:
    """Simple token bucket rate limiter."""
    min_interval: float
    last_call: float = field(default_factory=time. monotonic)

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
    api_key: str
    client_id: str
    client_secret: str
    user_agent: str
    num_comments: int = 50
    num_posts: int = 20
    threshold: float = 0.7
    output: Path = Path("flagged_content.csv")
    rate_per_min: float = DEFAULT_RATE_PER_MIN
    max_retries: int = DEFAULT_MAX_RETRIES
    timeout: int = DEFAULT_TIMEOUT
    verbose: bool = False

    def validate(self) -> None:
        """Validate configuration values."""
        if not (0.0 <= self.threshold <= 1.0):
            raise ValueError("threshold must be in [0.0, 1.0]")
        if not self.api_key.strip():
            raise ValueError("perspective_api_key cannot be empty")
        if not self.client_id.strip():
            raise ValueError("client_id cannot be empty")


def parse_args() -> Config:
    """Parse and validate CLI arguments."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("username", help="Reddit username (without u/)")
    p.add_argument(
        "--comments",
        type=int,
        default=50,
        help="Num comments to fetch",
    )
    p.add_argument(
        "--posts", type=int, default=20, help="Num posts to fetch"
    )
    p.add_argument(
        "--toxicity_threshold",
        type=float,
        default=0.7,
        help="Flag threshold",
    )
    p.add_argument(
        "--perspective_api_key", required=True, help="Perspective key"
    )
    p. add_argument("--client_id", required=True, help="Reddit client_id")
    p.add_argument(
        "--client_secret", required=True, help="Reddit client_secret"
    )
    p.add_argument(
        "--user_agent", required=True, help="Reddit user_agent"
    )
    p.add_argument(
        "--output", default="flagged_content.csv", help="CSV output"
    )
    p.add_argument(
        "--rate_per_min",
        type=float,
        default=DEFAULT_RATE_PER_MIN,
        help="Max Perspective req/min",
    )
    p.add_argument(
        "--max_retries", type=int, default=5, help="Max API retries"
    )
    p.add_argument(
        "--verbose", action="store_true", help="Verbose output"
    )
    args = p.parse_args()

    cfg = Config(
        username=args.username,
        api_key=args.perspective_api_key,
        client_id=args.client_id,
        client_secret=args.client_secret,
        user_agent=args.user_agent,
        num_comments=args.comments,
        num_posts=args.posts,
        threshold=args.toxicity_threshold,
        output=Path(args.output),
        rate_per_min=args.rate_per_min,
        max_retries=args.max_retries,
        verbose=args.verbose,
    )
    cfg.validate()
    return cfg


async def check_toxicity(
    text: str,
    client: httpx.AsyncClient,
    cfg: Config,
    limiter: RateLimiter,
) -> PerspectiveScore:
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
            return {
                k: v["summaryScore"]["value"]
                for k, v in result. get("attributeScores", {}). items()
            }
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                backoff = DEFAULT_BACKOFF_BASE * (2 ** (attempt - 1))
                if cfg.verbose:
                    print(
                        f"429 backoff {backoff:.1f}s "
                        f"({attempt}/{cfg.max_retries})",
                        file=sys.stderr,
                    )
                await asyncio. sleep(backoff)
                continue
            if 500 <= e.response.status_code < 600:
                await asyncio.sleep(2 ** (attempt - 1))
                continue
            print(f"HTTP {e.response.status_code}", file=sys.stderr)
            return {}
        except (httpx.TimeoutException, httpx.ConnectError) as e:
            if cfg.verbose:
                print(f"Network error: {e}", file=sys.stderr)
            await asyncio.sleep(2 ** (attempt - 1))
            continue
        except Exception as e:
            print(f"Unexpected: {e}", file=sys.stderr)
            return {}

    if cfg.verbose:
        print("Max retries exceeded", file=sys.stderr)
    return {}


async def analyze_content(
    items: list[tuple[str, str, str, float]],
    cfg: Config,
) -> list[FlaggedItem]:
    """Analyze list of content items concurrently.
    
    Args:
        items: List of (type, subreddit, text, timestamp) tuples
        cfg: Scanner config
        
    Returns:
        List of flagged items
    """
    limiter = RateLimiter(60.0 / cfg.rate_per_min)
    flagged: list[FlaggedItem] = []

    async with httpx.AsyncClient() as client:
        tasks = [
            check_toxicity(text, client, cfg, limiter)
            for _, _, text, _ in items
        ]
        scores_list = await asyncio.gather(*tasks)

    for (item_type, sub, text, ts), scores in zip(items, scores_list):
        if any(s >= cfg.threshold for s in scores. values()):
            flagged. append(
                FlaggedItem(
                    timestamp=time.strftime(
                        "%Y-%m-%d %H:%M:%S", time.localtime(ts)
                    ),
                    type=item_type,
                    subreddit=sub,
                    content=text,
                    **scores,  # type: ignore
                )
            )
    return flagged


def fetch_user_content(
    username: str, cfg: Config, reddit: praw.Reddit
) -> list[tuple[str, str, str, float]]:
    """Fetch user comments and posts.
    
    Args:
        username: Reddit username
        cfg: Scanner config
        reddit: PRAW client
        
    Returns:
        List of (type, subreddit, text, timestamp) tuples
    """
    items: list[tuple[str, str, str, float]] = []
    user = reddit.redditor(username)

    print(f"Fetching {cfg.num_comments} comments...")
    for comment in user.comments. new(limit=cfg.num_comments):
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
        items.append(
            ("post", str(post.subreddit), text, post.created_utc)
        )

    return items


def save_results(flagged: list[FlaggedItem], path: Path) -> None:
    """Save flagged items to CSV.
    
    Args:
        flagged: List of flagged content
        path: Output CSV path
    """
    if not flagged:
        print("No flagged content.")
        return

    df = pd.DataFrame(flagged)
    df.to_csv(path, index=False)
    print(f"Flagged {len(flagged)} items → {path}")


async def main_async() -> None:
    """Main async entry point."""
    cfg = parse_args()

    reddit = praw.Reddit(
        client_id=cfg.client_id,
        client_secret=cfg.client_secret,
        user_agent=cfg.user_agent,
    )

    try:
        items = fetch_user_content(cfg.username, cfg, reddit)
        print(f"Analyzing {len(items)} items...")
        flagged = await analyze_content(items, cfg)
        save_results(flagged, cfg. output)
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    """Synchronous entry point."""
    asyncio.run(main_async())


if __name__ == "__main__":
    main()
