#!/usr/bin/env python3
import argparse, asyncio, csv, json, sys, time, praw, httpx
from pathlib import Path

# Config & Consts
API_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
ATTRS = ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]

async def check(text, client, key, rate_limiter):
    if not text.strip(): return {}
    await rate_limiter()
    try:
        resp = await client.post(API_URL, params={"key": key}, timeout=10,
            json={"comment": {"text": text}, "languages": ["en"], "requestedAttributes": {a: {} for a in ATTRS}})
        resp.raise_for_status()
        return {k: v["summaryScore"]["value"] for k, v in resp.json().get("attributeScores", {}).items()}
    except Exception as e:
        sys.stderr.write(f"Err: {e}\n")
        return {}

async def main():
    p = argparse.ArgumentParser()
    p.add_argument("user"); p.add_argument("--key", required=True)
    p.add_argument("--cid", required=True); p.add_argument("--sec", required=True)
    p.add_argument("--ua", required=True); p.add_argument("--out", default="flagged.csv")
    p.add_argument("--limit", type=int, default=50); p.add_argument("--thresh", type=float, default=0.7)
    args = p.parse_args()

    # Rate Limiter Closure
    last_call = [0.0]
    async def limiter():
        elapsed = time.monotonic() - last_call[0]
        if elapsed < 1.0: await asyncio.sleep(1.0 - elapsed)
        last_call[0] = time.monotonic()

    # Fetch Reddit
    r = praw.Reddit(client_id=args.cid, client_secret=args.sec, user_agent=args.ua)
    u = r.redditor(args.user)
    items = []
    print(f"Fetching content for u/{args.user}...")
    try:
        items.extend([("cmt", c.subreddit.display_name, c.body, c.created_utc) for c in u.comments.new(limit=args.limit)])
        items.extend([("post", s.subreddit.display_name, f"{s.title}\n{s.selftext}", s.created_utc) for s in u.submissions.new(limit=args.limit)])
    except Exception as e: sys.exit(f"Reddit Error: {e}")

    # Analyze
    print(f"Analyzing {len(items)} items...")
    flagged = []
    async with httpx.AsyncClient() as client:
        tasks = [check(txt, client, args.key, limiter) for _, _, txt, _ in items]
        results = await asyncio.gather(*tasks)

    # Filter & Save
    for (kind, sub, txt, ts), scores in zip(items, results):
        if any(s >= args.thresh for s in scores.values()):
            row = {"ts": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)), 
                   "type": kind, "sub": sub, "text": txt, **scores}
            flagged.append(row)

    if flagged:
        with open(args.out, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["ts", "type", "sub", "text"] + ATTRS)
            w.writeheader()
            w.writerows(flagged)
        print(f"Done. {len(flagged)} flagged items saved to {args.out}")
    else:
        print("Clean scan. No toxic content found.")

if __name__ == "__main__":
    asyncio.run(main())
