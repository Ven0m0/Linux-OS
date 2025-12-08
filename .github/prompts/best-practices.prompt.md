# Best Practices Check

## Goal

Analyze code vs lang-spec standards (PEP8, ES6+, etc) for qual/maint.

## Rules

1. **ID**: Lang/Framework.
2. **Apply**: Offl guides/idioms.
3. **Context**: Respect exist patterns.
4. **Output**: Actionable > Nitpicks.

## Checks

- **Py**: PEP8, type hints, pythonic idioms, mods/pkgs.
- **JS/TS**: ES6+, Async/await, strict mode, err handle.
- **Web**: Comp struct, state mgmt, perf, a11y.
- **API**: RESTful, status codes, ver, docs.
- **Qual**: Naming, DRY, SRP, Err/Log, Perf (algos/cache), Test cov.

## Format

```markdown
## Review
**Sum**: Stack: []; Score: X/10; Key Improv: []
**Good**: [Prac 1, 2]
**Improv**:
1. **High**: [Name] (Curr -> Rec -> Why)
2. **Med**: ...
**Quick Wins**: [List]
```
