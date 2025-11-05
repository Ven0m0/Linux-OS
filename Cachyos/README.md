# Mirror & Keyserver Optimization Scripts

## Scripts

### mirror-rank.sh
Combined mirror optimization tool with fresh mirrorlist fetching.

**Features:**
- Fetches fresh Arch mirrorlist from archlinux.org with status filters
- Ranks all repos: Arch, CachyOS, Chaotic-AUR, EndeavourOS, ALHP, etc.
- Auto-discovers additional mirrorlists in /etc/pacman.d
- Backup system (keeps 20 most recent)
- Benchmark speeds with ping tests
- Interactive menu + CLI options
- Calls keyserver-rank automatically

**Usage:**
```bash
# Interactive menu
./mirror-rank.sh

# Optimize all (fetches fresh mirrors)
./mirror-rank.sh -o

# Optimize for specific country
./mirror-rank.sh -c US -o

# Benchmark current mirrors
./mirror-rank.sh -b

# Show current mirrorlist
./mirror-rank.sh -s
```

### keyserver-rank
Ranks GPG keyservers by response time, used by mirror-rank.sh.

**Features:**
- Tests keyservers in parallel
- Measures response time for key searches
- Auto-refresh pacman keys with fastest server

**Usage:**
```bash
# Rank and ask to refresh
./keyserver-rank

# Auto-refresh with fastest
./keyserver-rank --yes

# Just rank, don't refresh
./keyserver-rank --no

# Show fastest server only
./keyserver-rank --show-fastest
```

## Installation

```bash
# Install to /usr/local/bin or ~/.local/bin
sudo install -m755 mirror-rank.sh /usr/local/bin/
sudo install -m755 keyserver-rank /usr/local/bin/
```

## Dependencies

**Required:**
- curl or wget
- pacman

**Optional (ranked by preference):**
- rate-mirrors (recommended)
- cachyos-rate-mirrors (for CachyOS repos)
- reflector (fallback)

## Integration

mirror-rank.sh automatically calls keyserver-rank during optimization:
```bash
has keyserver-rank && sudo keyserver-rank --yes &>/dev/null || :
```

## Notes

- The keyserver-rank-helper script is deprecated (main script doesn't use it)
- Backups stored in /etc/pacman.d/.bak
- Logs to /var/log/mirror-rank.log
- Auto-detects country via ipapi.co
