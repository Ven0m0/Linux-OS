---
applyTo: "*"
description: "Performance optimization reference: frontend, backend, database best practices"
---

# Performance Optimization

## Principles

- **Measure first**: Profile before optimizing (Chrome DevTools, Lighthouse, cProfile, flame graphs)
- **Optimize common paths**: Focus on frequently executed code
- **Avoid premature optimization**: Clear code first, optimize when needed
- **Set budgets**: Define limits (load time, latency, memory) and enforce with CI/CD
- **Automate testing**: Catch performance regressions early

---

## Frontend

### Rendering & DOM

- Batch DOM updates (fragments, not loops)
- Virtual DOM: `React.memo`, `useMemo`, `useCallback`, stable keys in lists
- CSS animations > JS (GPU-accelerated)
- Defer non-critical work: `requestIdleCallback`

### Assets

- Images: Modern formats (WebP, AVIF), compression (ImageOptim, Squoosh)
- SVGs for icons; minify/bundle JS/CSS (Webpack, Rollup, esbuild); tree-shake dead code
- Lazy load: `loading="lazy"`, dynamic imports
- Fonts: Subset, `font-display: swap`

### Network

- Reduce HTTP requests (combine files, sprites, inline critical CSS)
- HTTP/2/3, CDNs, Service Workers, cache headers
- `defer`/`async` scripts, `<link rel="preload">`

### JavaScript

- Web Workers for heavy computation
- Debounce/throttle events (scroll, resize, input)
- Clean up listeners/intervals (avoid memory leaks)
- Efficient data structures: `Map`/`Set`, `TypedArray`

### Framework Tips

- **React**: `React.lazy`, `Suspense`, code-splitting, avoid anonymous functions in render
- **Angular**: OnPush change detection, `trackBy` in `ngFor`, lazy load modules
- **Vue**: Computed props > methods, `v-show` vs `v-if`, lazy load routes

### Monitor

- Core Web Vitals (LCP, FID, CLS)
- Chrome DevTools Performance tab
- Lighthouse, WebPageTest

---

## Backend

### Algorithms & Data

- Right data structure (hash maps for lookups, trees for hierarchy)
- Avoid O(n²): Profile nested loops/recursion
- Batch processing, streaming for large datasets

### Concurrency

- Async I/O: `async`/`await`, event loops
- Thread/worker pools, avoid race conditions
- Bulk operations, backpressure in queues

### Caching

- Redis/Memcached for hot data
- Invalidation: TTL, event-based, manual
- Cache stampede protection (locks, request coalescing)
- Don't cache volatile/sensitive data

### API & Network

- Minimize payloads: Compress (gzip, Brotli), pagination (cursors for real-time)
- Rate limiting, connection pooling
- HTTP/2, gRPC, WebSockets for high-throughput

### Logging

- Minimize logging in hot paths
- Structured logging (JSON), monitor latency/throughput/errors
- Alerts for performance regressions

### Language Tips

- **Node.js**: Async APIs, clustering/workers for CPU-bound, streams, profile with `clinic.js`
- **Python**: `asyncio`/`multiprocessing`, `lru_cache`, avoid GIL with C extensions
- **Java**: Thread pools (`Executors`), tune JVM (`-Xmx`, `-XX:+UseG1GC`)
- **.NET**: `async`/`await`, `Span<T>`, `IAsyncEnumerable<T>`

### Monitor

- Flame graphs (CPU), distributed tracing (OpenTelemetry, Jaeger)
- Heap dumps, slow query logs

---

## Database

### Queries

- **Indexes**: Use on frequently queried/filtered/joined columns; drop unused
- **Avoid SELECT ***: Select only needed columns
- **Parameterized queries**: Prevent SQL injection, improve caching
- **Avoid N+1**: Use joins or batch queries
- **LIMIT/OFFSET**: Paginate large results

### Schema

- Normalize for consistency, denormalize for read-heavy workloads
- Efficient data types, partitioning for large tables
- Archive old data, use foreign keys judiciously

### Connections

- Connection pooling, keep-alive
- Monitor active connections, tune pool size

### Caching

- Query result caching (Redis), materialized views
- Invalidate on writes

### NoSQL

- **MongoDB**: Indexes, `$project` to limit fields, sharding
- **Redis**: Pipelining, avoid `KEYS *`, use `SCAN`
- **Cassandra**: Partition keys for even distribution

### Monitor

- Slow query logs, `EXPLAIN` plans
- Connection pool stats, replication lag

---

## Infrastructure

### Horizontal Scaling

- Load balancing (round-robin, least-connections)
- Session affinity for stateful apps
- Auto-scaling based on metrics (CPU, latency)

### Vertical Scaling

- Increase CPU/RAM when horizontal scaling isn't feasible
- Profile first to ensure it's the bottleneck

### CDNs & Edge

- Cache static assets, geo-distribute
- Edge functions for low-latency compute

### Containers & Orchestration

- Right-size containers (CPU/memory limits)
- Use slim base images, multi-stage builds
- Kubernetes: HPA, resource requests/limits

### Observability

- Metrics: Prometheus, Grafana, Datadog
- Tracing: OpenTelemetry, Jaeger, Zipkin
- Logs: ELK stack, Loki

---

## Security & Performance

- Input validation (avoid regex DoS)
- Rate limiting (prevent abuse)
- Secure caching (don't cache sensitive data)
- TLS/SSL overhead (HTTP/2, session resumption)

---

## Checklist

**Frontend:**

- [ ] Images compressed, modern formats
- [ ] Lazy loading, code-splitting
- [ ] CDN for static assets
- [ ] Service Workers for caching
- [ ] Core Web Vitals monitored

**Backend:**

- [ ] Async I/O, connection pooling
- [ ] Caching (Redis), cache invalidation
- [ ] Rate limiting, monitoring (Prometheus)
- [ ] Flame graphs, distributed tracing

**Database:**

- [ ] Indexes on query columns
- [ ] Avoid N+1, SELECT *
- [ ] Slow query logs, EXPLAIN plans
- [ ] Connection pooling, replication

**Infrastructure:**

- [ ] Load balancing, auto-scaling
- [ ] CDN, edge caching
- [ ] Container resource limits
- [ ] Metrics, tracing, logs
