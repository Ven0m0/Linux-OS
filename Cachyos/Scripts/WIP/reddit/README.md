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
