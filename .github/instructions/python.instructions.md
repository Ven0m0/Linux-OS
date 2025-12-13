---
applyTo: "**/*.py"
description: "Python coding conventions and guidelines"
---

# Python Conventions

## Core

- **Style**: PEP 8; 4-space indent; max 80 chars.
- **Types**: Use `typing` (`List`, `Dict`, `Optional`); hints on all funcs.
- **Doc**: PEP 257 docstrings (Args/Returns) immediately after def.

## Quality

- **Funcs**: Small, atomic, descriptive names.
- **Readability**: Priority #1; comment complex algos/decisions.
- **Err**: Handle specific exceptions; no bare `except:`.
- **Test**: Unit tests for crit paths; cover edge cases (empty/invalid/large).

## Example

```python
def calc_area(r: float) -> float:
    """Calc circle area. Args: r(float). Ret: area(float)."""
    import math
    return math.pi * r ** 2
```
