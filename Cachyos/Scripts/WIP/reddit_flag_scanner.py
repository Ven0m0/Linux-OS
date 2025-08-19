import argparse
import praw
import pandas as pd
import time
import sys
import requests

PERSPECTIVE_API_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
REQUEST_TIMEOUT = 10  # seconds

def check_toxicity(text, api_key, attributes):
    headers = {"Content-Type": "application/json"}
    params = {"key": api_key}
    data = {
        "comment": {"text": text},
        "languages": ["en"],
        "requestedAttributes": {attr: {} for attr in attributes}
    }

    try:
        resp = requests.post(
            PERSPECTIVE_API_URL,
            headers=headers,
            params=params,
            json=data,
            timeout=REQUEST_TIMEOUT
        )
        resp.raise_for_status()
        result = resp.json()
        return {
            k: v["summaryScore"]["value"]
            for k, v in result.get("attributeScores", {}).items()
        }
    except Exception as e:
        print("Perspective API error:", e, file=sys.stderr)
        return {}

def main():
    parser = argparse.ArgumentParser(
        description="Scan a Reddit user's content for inappropriate material."
    )
    parser.add_argument("username", help="Reddit username (without u/)")
    parser.add_argument("--comments", type=int, default=50)
    parser.add_argument("--posts", type=int, default=20)
    parser.add_argument("--toxicity_threshold", type=float, default=0.7)
    parser.add_argument("--perspective_api_key", required=True, help="Perspective API key")
    parser.add_argument("--output", default="flagged_content.csv")
    args = parser.parse_args()

    reddit = praw.Reddit(
        client_id="YOUR_CLIENT_ID",
        client_secret="YOUR_CLIENT_SECRET",
        user_agent="scanner:v1.0 (by u/YourUsername)"
    )

    user = reddit.redditor(args.username)
    flagged = []

    print(f"Scanning u/{args.username}…")

    for comment in user.comments.new(limit=args.comments):
        scores = check_toxicity(
            comment.body, args.perspective_api_key,
            ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"]
        )
        if any(score >= args.toxicity_threshold for score in scores.values()):
            flagged.append({
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(comment.created_utc)),
                "type": "comment",
                "subreddit": str(comment.subreddit),
                "content": comment.body,
                **scores
            })

    for submission in user.submissions.new(limit=args.posts):
        fulltext = f"{submission.title}\n{submission.selftext}"
        scores = check_toxicity(fulltext, args.perspective_api_key,
                               ["TOXICITY", "INSULT", "PROFANITY", "SEXUALLY_EXPLICIT"])
        if any(score >= args.toxicity_threshold for score in scores.values()):
            flagged.append({
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(submission.created_utc)),
                "type": "post",
                "subreddit": str(submission.subreddit),
                "content": fulltext,
                **scores
            })

    if flagged:
        df = pd.DataFrame(flagged)
        df.to_csv(args.output, index=False)
        print(f"Flagged {len(flagged)} items. Saved to {args.output}")
    else:
        print("No inappropriate content detected.")

if __name__ == "__main__":
    main()
