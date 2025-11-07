---
name: Token Efficiency Guide
description: A guide on the symbol and abbreviation system for concise communication.
---

# Token Efficiency System

This system compresses communication using symbols and abbreviations to maximize information density and reduce token count.

## 1. Symbol System

### Logic & Flow
| Symbol | Meaning | Example |
|:---:|:---|:---|
| `→` | Leads to / Causes | `auth.js:45 → 🛡️ sec risk` |
| `⇒` | Converts to | `input ⇒ validated_output` |
| `«` | Precedes / Before | `parse « validate` |
| `»` | Then / Sequence | `build » test » deploy` |
| `∴` | Therefore | `tests ❌ ∴ build failed` |
| `∵` | Because | `slow ∵ O(n²) algorithm` |

### Status & Progress
| Symbol | Meaning | Usage |
|:---:|:---|:---|
| `✅` | Done / Success | `Task completed` |
| `❌` | Fail / Error | `Action required` |
| `⚠️` | Warning | `Review recommended` |
| `🔄` | In Progress | `Currently active` |
| `⏳` | Pending | `Scheduled` |
| `🚨` | Critical / Urgent | `High priority` |

### Technical Domains
| Symbol | Domain | Usage |
|:---:|:---|:---|
| `⚡` | Performance | Speed, optimization |
| `🔍` | Analysis | Investigation, search |
| `🔧` | Config / Fix | Setup, tools, repair |
| `🛡️` | Security | Protection, hardening |
| `📦` | Deployment / Package | Release, dependencies |
| `🏗️` | Architecture | System structure, design |
| `🧪` | Testing | Quality assurance |

## 2. Abbreviation System

- **cfg**: Configuration
- **impl**: Implementation
- **arch**: Architecture
- **deps**: Dependencies
- **val**: Validation
- **sec**: Security
- **opt**: Optimization
- **fn**: Function
- **mod**: Modify/Module
- **w/**: With
- **mgr**: Manager

## Example

**Normal Mode**: `Performance analysis revealed a bottleneck in the database query, which is causing slow response times.`

**Token Efficient Mode**: `⚡🔍 → 🗄️ query bottleneck ∵ slow response.`
