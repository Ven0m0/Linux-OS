#!/usr/bin/env python3
import argparse, asyncio, csv, json, shutil, sys, time, praw, httpx
from pathlib import Path

API_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
ATTRS = ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]

async def scan_sherlock(user, timeout, out_file):
    if not shutil.which("sherlock"): return print("Sherlock not installed.")
    print(f"🔎 Sherlock: Scanning '{user}'...")
    tmp = Path(f"/tmp/sh_{user}_{int(time.time())}.json")
    try:
        proc = await asyncio.create_subprocess_exec("sherlock", user, "--json", str(tmp), "--timeout", str(timeout), "--print-found", stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        await proc.communicate()
        if tmp.exists():
            data = json.loads(tmp.read_text())
            tmp.unlink()
            found = [{"platform": k, "url": d.get("url_user"), "status": d.get("status"), "response_time": d.get("response_time_s")} for k, d in data.items() if d.get("status") == "Claimed"]
            if found:
                with open(out_file, "w") as f: json.dump(found, f, indent=2)
                print(f"🔎 Sherlock: Found {len(found)} accounts -> {out_file}")
            return found
    except Exception as e: print(f"Sherlock error: {e}")
    return []

async def scan_reddit(args):
    last = [0.0]; delay = 60.0 / args.rate_per_min
    async def lim():
        now = time.monotonic(); elapsed = now - last[0]
        if elapsed < delay: await asyncio.sleep(delay - elapsed)
        last[0] = time.monotonic()

    print(f"🤖 Reddit: Fetching content for u/{args.username}...")
    try:
        r = praw.Reddit(client_id=args.cid, client_secret=args.sec, user_agent=args.ua)
        u = r.redditor(args.username)
        items = [("cmt", c.subreddit.display_name, c.body, c.created_utc) for c in u.comments.new(limit=args.comments)]
        items += [("post", s.subreddit.display_name, f"{s.title} {s.selftext}", s.created_utc) for s in u.submissions.new(limit=args.posts)]
    except Exception as e: return print(f"Reddit API Error: {e}")

    print(f"🤖 Reddit: Analyzing {len(items)} items...")
    async with httpx.AsyncClient() as cl:
        tasks = []
        for _, _, txt, _ in items:
            if not txt.strip(): tasks.append(asyncio.sleep(0, result={}))
            else:
                await lim()
                tasks.append(cl.post(API_URL, params={"key": args.key}, json={"comment": {"text": txt}, "languages": ["en"], "requestedAttributes": {a: {} for a in ATTRS}}, timeout=10))
        
        results = []
        for t in await asyncio.gather(*tasks, return_exceptions=True):
            if isinstance(t, httpx.Response) and t.status_code == 200:
                results.append({k: v["summaryScore"]["value"] for k, v in t.json().get("attributeScores", {}).items()})
            else: results.append({})

    flagged = []
    for (kind, sub, txt, ts), scores in zip(items, results):
        if any(s >= args.thresh for s in scores.values()):
            flagged.append({"timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)), "type": kind, "subreddit": sub, "content": txt[:500], **scores})

    if flagged:
        with open(args.out_red, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["timestamp", "type", "subreddit", "content"] + ATTRS)
            w.writeheader(); w.writerows(flagged)
        print(f"🤖 Reddit: Saved {len(flagged)} flagged items -> {args.out_red}")
    else: print("🤖 Reddit: Clean scan.")

async def main():
    p = argparse.ArgumentParser()
    p.add_argument("username")
    p.add_argument("--mode", choices=["sherlock", "reddit", "both"], default="both")
    p.add_argument("--perspective-api-key", dest="key"); p.add_argument("--client-id", dest="cid")
    p.add_argument("--client-secret", dest="sec"); p.add_argument("--user-agent", dest="ua")
    p.add_argument("--comments", type=int, default=50); p.add_argument("--posts", type=int, default=20)
    p.add_argument("--toxicity-threshold", dest="thresh", type=float, default=0.7)
    p.add_argument("--output-reddit", dest="out_red", default="reddit_flagged.csv")
    p.add_argument("--output-sherlock", dest="out_sher", default="sherlock_results.json")
    p.add_argument("--sherlock-timeout", type=int, default=60)
    p.add_argument("--rate-per-min", type=float, default=60.0)
    p.add_argument("--max-retries", type=int, default=5); p.add_argument("--verbose", action="store_true")
    args = p.parse_args()

    tasks = []
    if args.mode in ["sherlock", "both"]: tasks.append(scan_sherlock(args.username, args.sherlock_timeout, args.out_sher))
    if args.mode in ["reddit", "both"]:
        if not all([args.key, args.cid, args.sec, args.ua]): sys.exit("Error: Reddit mode requires API keys.")
        tasks.append(scan_reddit(args))
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
