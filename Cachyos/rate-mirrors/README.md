# cachyos-rate-mirrors Extended

**Multi-repo mirror ranking with archlinux.org pre-selection.**

## Features

- **Selectable repos** — `--repos arch,cachyos,alhp,chaotic` (default: all)
- **Archlinux.org API** — Pre-ranked arch mirrors (HTTPS+IPv4, country-optimized)
- **Country override** — `--country FR` (auto-detects, defaults to DE)
- **Zero new deps** — Uses curl/rate-mirrors/pacman only
- **Unified loop** — Metadata-driven processing for all repos

## Usage

```bash
# Default (all repos, auto-country)
sudo cachyos-rate-mirrors

# Specific repos
sudo cachyos-rate-mirrors --repos arch,cachyos
sudo cachyos-rate-mirrors --repos alhp

# Override country
sudo cachyos-rate-mirrors --country FR
sudo cachyos-rate-mirrors --country RU --repos arch

# Combined
sudo cachyos-rate-mirrors --country AT --repos arch,cachyos,alhp
```

## Behavior

1. **Country detection** — Via geoip.kde.org → fallback to DE
2. **Arch mirrors** — Fetches from `archlinux.org/mirrorlist/?country=XX&protocol=https&ip_version=4`
3. **Rate-mirrors** — Ranks cachyos, alhp, chaotic with rate-mirrors CLI
4. **Special rules**:
   - Arch+RU → Yandex mirror prepended
   - CachyOS+!RU → CDN77 (archlinux.cachyos.org) prepended
   - CachyOS+RU → archlinux.gay + Yandex prepended
5. **Variants** — Creates `*-v3-mirrorlist` and `*-v4-mirrorlist` for cachyos only
6. **Permissions** — Ensures go+r for Aura compatibility
7. **Backups** — All originals backed up with `-backup` suffix

## Files Modified

- `/etc/pacman.d/mirrorlist` — Arch
- `/etc/pacman.d/cachyos-mirrorlist` — CachyOS (+ v3/v4 variants)
- `/etc/pacman.d/alhp-mirrorlist` — ALHP
- `/etc/pacman.d/chaotic-mirrorlist` — Chaotic

## Systemd

```bash
# Enable auto-ranking (runs on boot+15s, then every 12h)
systemctl enable --now cachyos-rate-mirrors.timer

# Manual run
systemctl start cachyos-rate-mirrors.service
```

## Building

```bash
makepkg -si
```

Update checksums:
```bash
sha256sum cachyos-rate-mirrors cachyos-rate-mirrors.{service,timer,hook}
```

## Requirements

- Root access
- `rate-mirrors` package
- `curl` (system utility)
- `pacman` (implicit)

## Optimizations

- **38% size reduction** (201→125 LOC)
- Inline color setup, consolidated msg functions
- Parameter expansion for arch mirror parsing (sed-only)
- IFS-based array split (no fork)
- Merged special handlers, deduplicated backup logic
- Reduced subprocess overhead in country detection
