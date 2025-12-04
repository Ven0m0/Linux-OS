# Context Optimization Protocol

## Objective
Reduce tokens via dedup/pruning; maintain info density.

## Analysis
1. **Audit:** `find . -name "CLAUDE-*.md" ...` (Target >20KB).
2. **Scope:** REMOVED/DEPRECATED, generated/tmp, duplicates.

## Strategy (Priority Order)
1. **Prune (Highest):** Delete obsolete/tmp files. Clean refs.
2. **Consolidate (High):** Merge overlapping (Sec, Perf, Arch) → `*-comprehensive.md`.
   - *Reqs:* Keep impl details, snippets, troubleshooting.
3. **Streamline (Med):** Summarize `CLAUDE.md`. Remove verbose arch/setup.
4. **Archive (Med):** Move resolved/historic → `archive/`. Index in `archive/README.md`.

## Standards
- **File Fmt:** `[topic]-comprehensive.md`
- **Struct:** Status/Cov → Exec Summary → Sections → Cross-cutting.
- **QA:** Validate savings; ensure no tech data loss.

## Maintenance
- **Cycle:** Monthly prune; Qtly consolidate.
- **Trigger:** Size bloat, new overlaps.
