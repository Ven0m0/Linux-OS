#!/usr/bin/env python3

# Dependencies:
# pacman -S python-praw python-pandas python-google-api-python-client
# Alternatively if not on archlinux:
# pip install praw requests pandas
#
# Needed:
# Fill in USERNAME, API_KEY, CLIENT_ID and CLIENT_SECRET
# You need a reddit dev app and a Perspective API key (free)
# https://support.perspectiveapi.com/s/docs-enable-the-api
# https://developers.perspectiveapi.com/s/docs-get-started
# https://www.reddit.com/prefs/apps
# https://cloud.google.com/docs/authentication/api-keys
#
# Usage:
# python reddit_flag_scanner.py USERNAME \
#  --comments 100 \
#  --posts 50 \
#  --toxicity_threshold 0.7 \
#  --perspective_api_key API_KEY \
#  --client_id CLIENT_ID \
#  --client_secret CLIENT_SECRET \
#  --user_agent "script:myapp:v1.0 (by u/YourUsername)" \
#  --output flagged.csv

import argparse
import praw
import pandas as pd
import time
import sys
import requests
import random
from typing import Dict

PERSPECTIVE_API_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
REQUEST_TIMEOUT = 10  # seconds


def make_session() -> requests.Session:
    s = requests.Session()
    s.headers.update({"Content-Type": "application/json"})
    return s


def check_toxicity(
    text: str,
    api_key: str,
    attributes,
    session: requests.Session,
    min_interval: float,
    max_retries: int = 5,
    backoff_base: float = 1.0,
) -> Dict[str, float]:
    """
    Send a request to Perspective with retries and rate-limiting.
    Returns a dict of scores or empty dict on persistent failure.
    """
    if not text or not text.strip():
        return {}

    params = {"key": api_key}
    payload = {
        "comment": {"text": text},
        "languages": ["en"],
        "requestedAttributes": {attr: {} for attr in attributes},
    }

    # Rate limiting: ensure at least min_interval seconds between calls.
    # We'll store timestamp on the session object.
    last_ts = getattr(session, "_last_call_ts", None)
    if last_ts is not None:
        elapsed = time.monotonic() - last_ts
        if elapsed < min_interval:
            time.sleep(min_interval - elapsed)

    for attempt in range(1, max_retries + 1):
        try:
            resp = session.post(
                PERSPECTIVE_API_URL,
                params=params,
                json=payload,
                timeout=REQUEST_TIMEOUT,
            )
            # Store timestamp regardless of outcome to keep spacing consistent
            session._last_call_ts = time.monotonic()

            # Raise for HTTP errors (will be caught below)
            resp.raise_for_status()
            result = resp.json()
            return {
                k: v["summaryScore"]["value"]
                for k, v in result.get("attributeScores", {}).items()
            }

        except requests.HTTPError as http_err:
            code = getattr(http_err.response, "status_code", None)
            # 429 -> Too Many Requests: backoff & retry
            if code == 429:
                backoff = backoff_base * (2 ** (attempt - 1)) + random.uniform(0, 0.5)
                print(
                    f"Perspective API 429 — backoff {backoff:.2f}s (attempt {attempt}/{max_retries})",
                    file=sys.stderr,
                )
                time.sleep(backoff)
                continue
            # For 5xx server errors, also retry
            if code and 500 <= code < 600:
                backoff = backoff_base * (2 ** (attempt - 1)) + random.uniform(0, 0.5)
                print(
                    f"Perspective API server error {code} — retrying in {backoff:.2f}s (attempt {attempt}/{max_retries})",
                    file=sys.stderr,
                )
                time.sleep(backoff)
                continue
            # For 4xx other than 429, don't retry
            print(f"Perspective API HTTP error {code}: {http_err}", file=sys.stderr)
            return {}
        except (requests.ConnectionError, requests.Timeout) as err:
            backoff = backoff_base * (2 ** (attempt - 1)) + random.uniform(0, 0.5)
            print(
                f"Network error {err} — retrying in {backoff:.2f}s (attempt {attempt}/{max_retries})",
                file=sys.stderr,
            )
            time.sleep(backoff)
            continue
        except Exception as e:
            print("Perspective API unexpected error:", e, file=sys.stderr)
            return {}

    print("Perspective API: exceeded max retries, skipping item.", file=sys.stderr)
    return {}


def main():
    parser = argparse.ArgumentParser(
        description="Scan a Reddit user's content for inappropriate material."
    )
    parser.add_argument("username", help="Reddit username (without u/)")
    parser.add_argument(
        "--comments", type=int, default=50, help="Number of comments to fetch"
    )
    parser.add_argument(
        "--posts", type=int, default=20, help="Number of submissions to fetch"
    )
    parser.add_argument(
        "--toxicity_threshold", type=float, default=0.7, help="Threshold for flagging"
    )
    parser.add_argument(
        "--perspective_api_key", required=True, help="Perspective API key"
    )
    parser.add_argument("--client_id", required=True, help="Reddit API client_id")
    parser.add_argument(
        "--client_secret", required=True, help="Reddit API client_secret"
    )
    parser.add_argument("--user_agent", required=True, help="Reddit user_agent string")
    parser.add_argument(
        "--output", default="flagged_content.csv", help="CSV output filename"
    )
    parser.add_argument(
        "--rate_per_min",
        type=float,
        default=60.0,
        help="Max Perspective requests per minute (default 60). Use lower if you hit quota.",
    )
    parser.add_argument(
        "--max_retries",
        type=int,
        default=5,
        help="Max retries for Perspective API calls",
    )
    args = parser.parse_args()

    # Derived
    min_interval = 60.0 / float(max(1.0, args.rate_per_min))  # seconds between calls

    # Init reddit
    reddit = praw.Reddit(
        client_id=args.client_id,
        client_secret=args.client_secret,
        user_agent=args.user_agent,
    )

    session = make_session()
    flagged = []

    print(f"Scanning u/{args.username}…")
    try:
        user = reddit.redditor(args.username)

        # Comments
        for i, comment in enumerate(user.comments.new(limit=args.comments), start=1):
            text = comment.body or ""
            scores = check_toxicity(
                text,
                args.perspective_api_key,
                ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"],
                session,
                min_interval,
                max_retries=args.max_retries,
            )
            if any(score >= args.toxicity_threshold for score in scores.values()):
                flagged.append(
                    {
                        "timestamp": time.strftime(
                            "%Y-%m-%d %H:%M:%S", time.localtime(comment.created_utc)
                        ),
                        "type": "comment",
                        "subreddit": str(comment.subreddit),
                        "content": text,
                        **scores,
                    }
                )
            print(
                f"[comments {i}/{args.comments}] checked — flagged so far: {len(flagged)}",
                end="\r",
            )

        print()  # newline after progress line

        # Submissions
        for i, submission in enumerate(user.submissions.new(limit=args.posts), start=1):
            fulltext = (
                f"{submission.title}\n{submission.selftext}"
                if (submission.title or submission.selftext)
                else ""
            )
            scores = check_toxicity(
                fulltext,
                args.perspective_api_key,
                ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"],
                session,
                min_interval,
                max_retries=args.max_retries,
            )
            if any(score >= args.toxicity_threshold for score in scores.values()):
                flagged.append(
                    {
                        "timestamp": time.strftime(
                            "%Y-%m-%d %H:%M:%S", time.localtime(submission.created_utc)
                        ),
                        "type": "post",
                        "subreddit": str(submission.subreddit),
                        "content": fulltext,
                        **scores,
                    }
                )
            print(
                f"[posts {i}/{args.posts}] checked — flagged so far: {len(flagged)}",
                end="\r",
            )

        print()  # newline

    except KeyboardInterrupt:
        print("\nInterrupted by user. Saving results so far...", file=sys.stderr)

    # Save results
    if flagged:
        df = pd.DataFrame(flagged)
        df.to_csv(args.output, index=False)
        print(f"Flagged {len(flagged)} items. Saved to {args.output}")
    else:
        print("No inappropriate content detected (or none flagged).")


if __name__ == "__main__":
    main()
