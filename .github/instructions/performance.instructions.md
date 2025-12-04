---
applyTo: "*"
---

# Perf Opt Best Practices

## General
- **Rule**: Measure » Optimize. ❌ Guess.
- **Focus**: Common paths; ignore rare edge cases.
- **Res**: Min usage (CPU/Mem/Net). Simplicity > Cleverness.

## 🎨 Frontend
- **DOM**: Min manipulations; use VirtDOM (React/Vue).
- **Assets**: Compress imgs (WebP/AVIF); lazy load (`loading="lazy"`); minify JS/CSS.
- **Net**: HTTP/2+3; CDN; Cache headers; Defer/Async scripts.
- **JS**: No main thread block (Workers); debounce events; avoid globals/leaks.
- **React**: `React.memo`, `useMemo`, `useCallback`; split bundles.

## ⚙️ Backend
- **Algo**: O(n) > O(n²); efficient structs (Map/Set); async I/O.
- **Conc**: Async/await; thread pools; avoid race cond.
- **Cache**: Redis/Memcached for hot data; handle invalidation/stampedes.
- **API**: Gzip/Brotli; paginate lists; rate limit; connection pool.
- **Langs**:
  - **Node**: Async always; cluster/workers; streams.
  - **Py**: Built-in structs; `cProfile`; `multiprocessing`; `lru_cache`.
  - **Rust/Go/Java**: Concurrency primitives; profile; memory safe patterns.

## 🗄️ Database
- **Query**: Index freq cols; ❌ `SELECT *`; use `EXPLAIN`; avoid N+1.
- **Schema**: Normalize (mostly); partition large tables; archive old data.
- **Tx**: Short transactions; lowest safe isolation.
- **NoSQL**: Design for access pattern; distrib keys evenly.

## ⚡ Checklist
- [ ] Complexity O(n) or better?
- [ ] Caching impl & valid?
- [ ] N+1 queries removed?
- [ ] Payload minimized/compressed?
- [ ] Assets opt & lazy?
- [ ] Blocking I/O removed?
