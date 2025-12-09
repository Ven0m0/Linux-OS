# Account Scanner

Multi-source account intelligence: Reddit toxicity analysis + Sherlock OSINT platform discovery.

## Features

- **Sherlock Mode**: Discover username presence across 400+ platforms
- **Reddit Mode**: Scan user content for toxicity via Google Perspective API
- **Both Mode**: Run both scanners concurrently for comprehensive analysis

## Installation

### Arch Linux / CachyOS

```bash
# Core dependencies
pacman -S python-praw python-httpx

# Sherlock
yay -S sherlock-git

# Optional: faster JSON parsing
pacman -S python-orjson
```

### Debian / Termux

```bash
# Using uv (recommended)
uv pip install praw pandas httpx sherlock-project orjson

# Or pip
pip3 install praw pandas httpx sherlock-project orjson
```

## Usage

### Mode 1: Sherlock Only

Discover platform presence without Reddit credentials:

```bash
./account_scanner.py username --mode sherlock
./account_scanner.py username --mode sherlock --sherlock-timeout 30 --verbose
```

### Mode 2: Reddit Only

Analyze toxicity without Sherlock:

```bash
./account_scanner.py username \
  --mode reddit \
  --perspective-api-key YOUR_KEY \
  --client-id YOUR_CLIENT_ID \
  --client-secret YOUR_SECRET \
  --user-agent "YourBot/1.0"
```

### Mode 3: Both (Default)

Full analysis with concurrent execution:

```bash
./account_scanner.py username \
  --mode both \
  --perspective-api-key YOUR_KEY \
  --client-id YOUR_CLIENT_ID \
  --client-secret YOUR_SECRET \
  --user-agent "YourBot/1.0" \
  --comments 100 \
  --posts 50 \
  --toxicity-threshold 0.6
```

## Configuration Options

### Reddit Scanner

```
--comments N              Number of comments to fetch (default: 50)
--posts N                 Number of posts to fetch (default: 20)
--toxicity-threshold F    Flag threshold 0.0-1.0 (default: 0.7)
--perspective-api-key K   Google Perspective API key (required for reddit mode)
--client-id ID            Reddit app client_id (required for reddit mode)
--client-secret S         Reddit app client_secret (required for reddit mode)
--user-agent UA           Reddit user agent (required for reddit mode)
--output-reddit FILE      Output CSV path (default: reddit_flagged.csv)
--rate-per-min N          Max Perspective requests/min (default: 60)
--max-retries N           API retry attempts (default: 5)
```

### Sherlock Scanner

```
--output-sherlock FILE    Output JSON path (default: sherlock_results.json)
--sherlock-timeout N      Timeout per site in seconds (default: 60)
```

### Global

```
--mode {sherlock,reddit,both}  Scanner mode (default: both)
--verbose                      Verbose output
```

## API Keys

### Reddit API

1. Visit https://www.reddit.com/prefs/apps
2. Create app → script type
3. Note client_id and client_secret

### Perspective API

1. Visit https://developers.perspectiveapi.com/s/docs-get-started
2. Enable API in Google Cloud Console
3. Create credentials → API key

## Output Format

### Sherlock Results (JSON)

```json
[
  {
    "platform": "GitHub",
    "url": "https://github.com/username",
    "status": "Claimed",
    "response_time": 0.234
  }
]
```

### Reddit Results (CSV)

```csv
timestamp,type,subreddit,content,TOXICITY,INSULT,PROFANITY,SEXUALLY_EXPLICIT
2024-12-01 14:30:22,comment,AskReddit,Some text...,0.85,0.42,0.31,0.12
```

## Performance

- **Concurrent execution**: Both scanners run in parallel when `--mode both`
- **Async HTTP**: Non-blocking Perspective API requests with rate limiting
- **Efficient parsing**: Optional orjson for 2-3x faster JSON operations
- **Minimal overhead**: Direct subprocess execution for Sherlock

## Examples

### Quick username check

```bash
# Just check platform presence
./account_scanner.py suspicious_user --mode sherlock --verbose
```

### Comprehensive audit

```bash
# Full scan with custom thresholds
./account_scanner.py target_user \
  --mode both \
  --perspective-api-key $PERSPECTIVE_KEY \
  --client-id $REDDIT_ID \
  --client-secret $REDDIT_SECRET \
  --user-agent "AuditBot/1.0" \
  --comments 200 \
  --toxicity-threshold 0.5 \
  --output-reddit audit_toxicity.csv \
  --output-sherlock audit_platforms.json \
  --verbose
```

### Monitor specific user

```bash
# Low threshold, high coverage
./account_scanner.py monitored_user \
  --mode reddit \
  --perspective-api-key $KEY \
  --client-id $ID \
  --client-secret $SECRET \
  --user-agent "Monitor/1.0" \
  --comments 500 \
  --posts 100 \
  --toxicity-threshold 0.3 \
  --rate-per-min 100
```

## Validation

```bash
# Check Sherlock installation
sherlock --version

# Lint
ruff check account_scanner.py

# Type check
mypy account_scanner.py

# Format
ruff format account_scanner.py
```

## Troubleshooting

### Sherlock not found

```bash
# Arch
yay -S sherlock-git

# Debian/Termux
pip install sherlock-project
```

### Rate limit errors (429)

- Reduce `--rate-per-min` value
- Increase `--max-retries`
- Script auto-implements exponential backoff

### PRAW authentication

- Verify credentials in Reddit app settings
- Check user_agent format: "AppName/Version"
- Ensure script type app (not web/installed)

## License

Follow Sherlock and Reddit API terms of service. Use responsibly for legitimate account analysis only.
