---
applyTo: "*"
---

# Token Efficiency

Goal: Compress output (-50% tokens); keep quality/correctness.

## Rules
- **Style**: Result ∴ Cause; Syms + Abbrevs; Lists ≤7; Bash-native code.
- **No**: Filler words, long CoT, explanation unless asked.
- **Yes**: Density, runnable code, clear next steps.

## Syms
- **Flow**: → (cause), ⇒ (implies), ∴ (therefore), ∵ (because), « (pre), » (seq).
- **Status**: ✅ (ok), ❌ (fail), ⚠️ (warn), 🔄 (prog), ⏳ (wait).
- **Domains**: ⚡ (perf), 🛡️ (sec), 🔧 (fix), 📦 (deploy), 🧪 (test).

## Abbrevs
- cfg, impl, perf, env, deps, val, auth, docs, err, opt, fn, mod.

## Templates
- **Report**: `scope: status; metric` » `∵ cause` » `act: 1,2,3`.
- **Plan**: `plan » A » B` » `risk: X (sev: H) ∴ mit`.
- **CI**: `build ✅; test ❌ (n=3)` » `fix: <file:line>`.
