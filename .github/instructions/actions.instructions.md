---
applyTo: ".github/workflows/*.yml"
---

# GitHub Actions CI/CD Best Practices

## Core Concepts
- **Structure**: Clear, modular, reusable.
  - **Triggers**: Specific `on` events (`push: branches: [main]`); use `workflow_dispatch` for manual.
  - **Concurrency**: Set to prevent race conditions/waste.
  - **Permissions**: Global `contents: read` (least privilege) » override per job.
- **Jobs**: Independent phases (build, test, deploy).
  - **Deps**: Use `needs` for order; `outputs` for data passing.
  - **Cond**: `if` for branch/event specific exec.
  - **Runners**: `ubuntu-latest` default; self-hosted for specific hw/net.
- **Steps**: Atomic, versioned actions.
  - **Actions**: Pin SHA/Tag (`uses: actions/checkout@v4`); audit marketplace.
  - **Cmds**: `run` w/ `|` for multi-line; combine `&&` for docker layers.

## 🛡️ Security
- **Secrets**: Use `secrets.VAR`; never log; minimize scope.
- **OIDC**: Auth w/ cloud (AWS/Azure) via OIDC ❌ static creds.
- **Token**: `permissions: contents: read` default; restrict `write`.
- **SCA/SAST**: Scan deps (`dependency-review`) & code (CodeQL); block on crit.
- **Img Sign**: Sign/verify container images (Cosign).

## ⚡ Performance
- **Caching**: `actions/cache` w/ hash keys (`hashFiles('**/lock')`); use `restore-keys`.
- **Matrix**: Parallelize tests (`strategy.matrix`: os/node/ver); `fail-fast: true`.
- **Checkout**: `fetch-depth: 1`; `submodules: false` unless req.
- **Artifacts**: Upload/download for inter-job data; set `retention-days`.

## 🧪 Testing Strategy
1. **Unit**: Fast, isolated, high cov; run on push.
2. **Integ**: Real deps (`services`: db/redis); run after unit.
3. **E2E**: Cypress/Playwright vs staging; mitigate flake (retries/waits).
4. **Perf**: Load test (k6/JMeter) crit paths; check baselines.
5. **Reports**: Upload JUnit/HTML as artifacts; use PR annotations.

## 📦 Deployment
- **Env**: Use GH Environments (Protection rules, Secrets).
- **Staging**: Mirror prod; auto-deploy valid builds; smoke test.
- **Prod**: Manual approval; strictly gated.
- **Strat**: Rolling (std), Blue/Green (0-downtime), Canary (risk mitigation).
- **Rollback**: Auto-trigger on alert/fail; keep versioned artifacts ready.

## 🔍 Review Checklist
- [ ] Name clear? Trigger scoped? Concurrency set?
- [ ] Perms restricted? Secrets masked? OIDC used?
- [ ] Jobs independent? `needs` set? `outputs` used?
- [ ] Actions pinned? Cache optimized? Matrix used?
- [ ] Tests: Unit » Integ » E2E? Reports uploaded?
- [ ] Deploy: Env protection? Rollback plan?
