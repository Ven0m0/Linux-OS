#!/usr/bin/env python3
import argparse, asyncio, csv, json, shutil, sys, time, praw, httpx
from pathlib import Path

# Consts
API_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
ATTRS = ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]

async def sherlock_scan(user, timeout):
    if not shutil.which("sherlock"): return print("Sherlock not installed.")
    print(f"🔎 Sherlock: Scanning '{user}'...")
    tmp = Path(f"/tmp/sh_{user}_{int(time.time())}.json")
    try:
        proc = await asyncio.create_subprocess_exec("sherlock", user, "--json", str(tmp), "--timeout", str(timeout),
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        await proc.communicate()
        if tmp.exists():
            data = json.loads(tmp.read_text())
            tmp.unlink()
            found = [d | {"platform": k} for k, d in data.items() if d.get("status") == "Claimed"]
            print(f"🔎 Sherlock: Found {len(found)} accounts.")
            return found
    except Exception as e: print(f"Sherlock err: {e}")
    return []

async def toxicity_scan(args):
    # Rate limiter
    lc = [0.0]
    async def lim():
        el = time.monotonic() - lc[0]
        if el < 1.0: await asyncio.sleep(1.0 - el)
        lc[0] = time.monotonic()

    r = praw.Reddit(client_id=args.cid, client_secret=args.sec, user_agent=args.ua)
    u = r.redditor(args.user)
    items = []
    print(f"🤖 Reddit: Fetching content...")
    try:
        items.extend([("cmt", c.subreddit.display_name, c.body, c.created_utc) for c in u.comments.new(limit=args.lim)])
        items.extend([("post", s.subreddit.display_name, f"{s.title} {s.selftext}", s.created_utc) for s in u.submissions.new(limit=args.lim)])
    except Exception as e: return print(f"Reddit API Err: {e}")

    print(f"🤖 Reddit: Analyzing {len(items)} items...")
    async with httpx.AsyncClient() as cl:
        tasks = []
        for _, _, txt, _ in items:
            if not txt.strip(): tasks.append(asyncio.sleep(0, result={}))
            else:
                await lim() # Throttle creation slightly to space requests
                tasks.append(cl.post(API_URL, params={"key": args.key}, timeout=10,
                    json={"comment": {"text": txt}, "languages": ["en"], "requestedAttributes": {a:{} for a in ATTRS}}))
        
        # Gather and process
        res_raw = await asyncio.gather(*tasks, return_exceptions=True)
        
    flagged = []
    for (kind, sub, txt, ts), res in zip(items, res_raw):
        if isinstance(res, httpx.Response) and res.status_code == 200:
            scores = {k: v["summaryScore"]["value"] for k,v in res.json().get("attributeScores",{}).items()}
            if any(s >= args.thresh for s in scores.values()):
                flagged.append({"ts": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)), 
                                "type": kind, "sub": sub, "text": txt[:200], **scores})
    
    if flagged:
        with open(args.out_red, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["ts","type","sub","text"]+ATTRS)
            w.writeheader(); w.writerows(flagged)
        print(f"🤖 Reddit: Saved {len(flagged)} flagged items.")
    else: print("🤖 Reddit: No toxicity found.")

async def main():
    p = argparse.ArgumentParser()
    p.add_argument("user")
    p.add_argument("--mode", choices=["sherlock", "reddit", "both"], default="both")
    p.add_argument("--key"); p.add_argument("--cid"); p.add_argument("--sec"); p.add_argument("--ua")
    p.add_argument("--out-red", default="flagged.csv"); p.add_argument("--out-sher", default="found.json")
    p.add_argument("--lim", type=int, default=50); p.add_argument("--thresh", type=float, default=0.7)
    args = p.parse_args()

    tasks = []
    if args.mode in ["sherlock", "both"]: tasks.append(sherlock_scan(args.user, 60))
    if args.mode in ["reddit", "both"]:
        if not all([args.key, args.cid, args.sec, args.ua]): sys.exit("Missing Reddit/Google keys.")
        tasks.append(toxicity_scan(args))
    
    results = await asyncio.gather(*tasks)
    
    # Save Sherlock results if they exist
    s_res = next((r for r in results if isinstance(r, list)), None)
    if s_res:
        with open(args.out_sher, "w") as f: json.dump(s_res, f, indent=2)
        print(f"🔎 Sherlock: Saved results to {args.out_sher}")

if __name__ == "__main__":
    asyncio.run(main())
