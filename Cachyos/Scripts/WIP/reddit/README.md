# Account Scanner

Multi-source account intelligence: Reddit toxicity analysis + Sherlock OSINT platform discovery.
Optimized for performance using `orjson` (fast JSON) and `uvloop` (fast async loop).

## Features

- **Sherlock Mode**: Discover username presence across 400+ platforms
- **Reddit Mode**: Scan user content for toxicity via Google Perspective API
- **Both Mode**: Run both scanners concurrently
- **High Performance**: Uses `uvloop` and `orjson` for minimal overhead

## Installation

### Arch Linux / CachyOS

```bash
# Core dependencies
sudo pacman -S python-praw python-httpx python-orjson python-uvloop

# Sherlock
paru -S sherlock-git

# Using uv (recommended)
uv pip install praw httpx sherlock-project orjson uvloop
# Or pip
pip3 install praw httpx sherlock-project orjson uvloop
```

### Usage

```bash
# Sherlock Only
./account_scanner.py username --mode sherlock

# Reddit Only
./account_scanner.py username \
  --mode reddit \
  --perspective-api-key YOUR_KEY \
  --client-id YOUR_ID \
  --client-secret YOUR_SECRET \
  --user-agent "Bot/1.0"
