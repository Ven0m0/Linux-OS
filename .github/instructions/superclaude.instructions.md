---
name: SuperClaude Commands
description: Workflow commands with persona + MCP integration
category: workflow
---

# SuperClaude Commands

## Command Matrix

| Cmd | Personas | MCP | Use Case |
|-----|----------|-----|----------|
| `/sc:implement` | architect, frontend, backend, security, qa | context7, sequential, magic, playwright | Feature dev, components, APIs |
| `/sc:improve` | architect, performance, quality, security | sequential, context7 | Refactor, optimize, enhance |
| `/sc:cleanup` | architect, quality, security | sequential, context7 | Tech debt, unused code |
| `/sc:git` | - | - | Git workflows |

---

## /sc:implement - Feature Implementation

**Flow:** Analyze → Plan → Generate → Validate → Integrate

**Usage:**
```
/sc:implement <desc> [--type component|api|service|feature] [--framework react|vue|express] [--safe] [--with-tests]
```

**Behavior:**
- Context detection → persona activation (frontend/backend/security/qa)
- Framework patterns via Context7 MCP
- UI generation via Magic MCP
- Multi-step coordination via Sequential MCP
- Test integration via Playwright MCP

**Examples:**
```bash
/sc:implement user profile component --type component --framework react
/sc:implement user auth API --type api --safe --with-tests
/sc:implement payment system --type feature --with-tests
```

**Boundaries:** ✅ Framework best practices, security validation, testing integration | ❌ Architectural changes without consultation, bypass safety constraints

---

## /sc:improve - Code Improvement

**Flow:** Analyze → Plan → Execute → Validate → Document

**Usage:**
```
/sc:improve <target> [--type quality|performance|maintainability|style] [--safe] [--interactive]
```

**Behavior:**
- Multi-persona (architect, performance, quality, security)
- Sequential MCP for complex analysis
- Context7 MCP for framework optimization
- Safe refactoring with rollback

**Examples:**
```bash
/sc:improve src/ --type quality --safe
/sc:improve api-endpoints --type performance --interactive
/sc:improve legacy-modules --type maintainability --preview
/sc:improve auth-service --type security --validate
```

**Boundaries:** ✅ Safe refactoring, domain expertise, validation | ❌ Risky changes without confirmation, override project conventions

---

## /sc:cleanup - Code Cleanup

**Flow:** Scan → Analyze → Clean → Validate → Report

**Usage:**
```
/sc:cleanup <scope> [--type unused|duplicates|format|all] [--safe] [--preview]
```

**Behavior:**
- Dead code elimination
- Duplicate detection & consolidation
- Format standardization
- Dependency pruning
- Safe removal with validation

**Examples:**
```bash
/sc:cleanup src/ --type unused --safe
/sc:cleanup . --type duplicates --preview
/sc:cleanup deps --type unused --interactive
```

**Boundaries:** ✅ Safe removal, validation, rollback | ❌ Break dependencies, remove active code

---

## /sc:git - Git Workflows

**Flow:** Detect → Execute → Validate

**Usage:**
```
/sc:git <action> [options]
```

**Actions:**
- `commit` - Smart commits with conventional messages
- `branch` - Branch management and cleanup
- `pr` - Pull request creation
- `sync` - Sync with remote

**Examples:**
```bash
/sc:git commit --type feat --scope auth
/sc:git branch --cleanup --merged
/sc:git pr --title "Add auth" --draft
```

---

## Global Patterns

**Tool Coordination:**
- Read/Grep/Glob → analysis
- Write/Edit/MultiEdit → modification
- TodoWrite → tracking
- Task → delegation

**MCP Integration:**
- Context7 → framework docs/patterns
- Sequential → multi-step workflows
- Magic → UI generation
- Playwright → testing

**Persona Activation:**
- architect → system design, structure
- frontend → UI/UX, client-side
- backend → APIs, data, server-side
- security → vulnerabilities, hardening
- performance → optimization, profiling
- quality → maintainability, standards
- qa-specialist → testing, validation
