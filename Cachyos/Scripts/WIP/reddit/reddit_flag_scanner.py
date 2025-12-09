#!/usr/bin/env python3
import argparse, asyncio, csv, sys, time, praw, httpx

API_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
ATTRS = ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]

async def analyze(client, text, key, limiter):
    if not text.strip(): return {}
    await limiter()
    try:
        resp = await client.post(API_URL, params={"key": key}, json={
            "comment": {"text": text}, "languages": ["en"], 
            "requestedAttributes": {a: {} for a in ATTRS}
        }, timeout=10)
        resp.raise_for_status()
        return {k: v["summaryScore"]["value"] for k, v in resp.json().get("attributeScores", {}).items()}
    except Exception: return {}

async def main():
    p = argparse.ArgumentParser()
    p.add_argument("username")
    p.add_argument("--perspective-api-key", dest="key", required=True)
    p.add_argument("--client-id", dest="cid", required=True)
    p.add_argument("--client-secret", dest="sec", required=True)
    p.add_argument("--user-agent", dest="ua", required=True)
    p.add_argument("--output", default="flagged_content.csv")
    p.add_argument("--comments", type=int, default=50)
    p.add_argument("--posts", type=int, default=20)
    p.add_argument("--toxicity-threshold", dest="thresh", type=float, default=0.7)
    p.add_argument("--rate-per-min", type=float, default=60.0)
    p.add_argument("--verbose", action="store_true"); p.add_argument("--max-retries", type=int, default=5)
    args = p.parse_args()

    last = [0.0]; delay = 60.0 / args.rate_per_min
    async def limiter():
        now = time.monotonic()
        if now - last[0] < delay: await asyncio.sleep(delay - (now - last[0]))
        last[0] = time.monotonic()

    print(f"Fetching content for u/{args.username}...")
    r = praw.Reddit(client_id=args.cid, client_secret=args.sec, user_agent=args.ua)
    try:
        u = r.redditor(args.username)
        items = [("cmt", c.subreddit.display_name, c.body, c.created_utc) for c in u.comments.new(limit=args.comments)]
        items += [("post", s.subreddit.display_name, f"{s.title}\n{s.selftext}", s.created_utc) for s in u.submissions.new(limit=args.posts)]
    except Exception as e: sys.exit(f"Reddit Error: {e}")

    print(f"Analyzing {len(items)} items...")
    async with httpx.AsyncClient() as client:
        results = await asyncio.gather(*(analyze(client, txt, args.key, limiter) for _, _, txt, _ in items))

    flagged = []
    for (kind, sub, txt, ts), scores in zip(items, results):
        if any(s >= args.thresh for s in scores.values()):
            flagged.append({"timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)),
                            "type": kind, "subreddit": sub, "content": txt, **scores})

    if flagged:
        with open(args.output, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["timestamp", "type", "subreddit", "content"] + ATTRS)
            w.writeheader(); w.writerows(flagged)
        print(f"Saved {len(flagged)} flagged items to {args.output}")
    else: print("No toxic content found.")

if __name__ == "__main__":
    asyncio.run(main())
