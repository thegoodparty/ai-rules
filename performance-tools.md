# Performance Tools — Cookbook

A companion to `performance.md`. Concrete commands for measuring, profiling, and benchmarking — so claims about performance can be backed by numbers instead of intuition.

**House rule:** any PR that says "this is faster" must include a measurement from one of these tools (or production telemetry). Without that, it's a refactor.

Each section lists:

- **What it measures** — the question the tool answers
- **Install** — one-line setup
- **Run** — copy-paste command
- **Read** — what to look for in the output

Most repos also ship convenience wrappers under `scripts/perf/`. Prefer those when they exist — they encode the right defaults for that repo.

---

## 0. Universal: hyperfine — "did my change help, with statistical confidence?"

The single highest-leverage tool. Wraps any command, runs warmup + multiple iterations, reports mean / median / stddev / min / max. Use it to compare any two commits, branches, or scripts.

**Install:**
```bash
brew install hyperfine        # macOS
cargo install hyperfine       # Linux/anywhere with cargo
```

**Run — compare two branches of a script:**
```bash
hyperfine --warmup 3 --runs 20 \
  'git stash && npm run my-script' \
  'git stash pop && npm run my-script'
```

**Run — compare two commands side by side:**
```bash
hyperfine --warmup 3 \
  'node dist/old.js' \
  'node dist/new.js'
```

**Read:** mean ± stddev tells you the size of the change *and* whether it's statistically meaningful. If stddev ≥ the difference between means, your "improvement" is noise.

**When NOT to use:** sub-millisecond operations (the JS startup cost dominates). Use a microbenchmark library instead (see §7).

---

## 1. HTTP load — autocannon — "how does this endpoint behave under load?"

Single-endpoint load tester with rich latency stats. Best for "is endpoint X faster after my change?" and for catching tail latency that single-shot curl misses.

**Install:**
```bash
npm i -g autocannon
```

**Run:**
```bash
# 10 connections, 30s duration, with worker pipelining
autocannon -c 10 -d 30 -p 1 http://localhost:3000/health

# POST with JSON body and auth header
autocannon -c 20 -d 30 \
  -m POST \
  -H 'content-type: application/json' \
  -H 'authorization: Bearer dev-token' \
  -b '{"foo":"bar"}' \
  http://localhost:3000/api/things
```

**Read:** the latency table (`avg`, `p50`, `p95`, `p99`, `p99.9`, `max`). p99 is where slow paths hide; if `max` is 10× `p99`, you have GC pauses or lock contention.

**Repo wrappers:** `scripts/perf/bench-endpoint.sh` in each NestJS service and `scripts/perf/bench-route.sh` in `gp-webapp`.

---

## 2. Multi-endpoint scenarios — k6 — "how does the whole journey behave?"

For load-testing realistic flows (login → list → detail → mutate) rather than one endpoint in isolation. Already in use in `people-api/perf/`.

**Install:**
```bash
brew install k6
```

**Run an existing scenario (people-api):**
```bash
k6 run --summary-trend-stats "avg,med,p(50),p(95),p(99),min,max" perf/mixed.ts
```

**Read:** per-scenario thresholds (`http_req_duration`, `http_req_failed`), and the trend stats per checkpoint.

**Add a scenario:** copy `people-api/perf/people-get.ts` as a template.

---

## 3. Node CPU profile — built-in V8 sampler — "where is the CPU going?"

Zero install. Produces a sorted text report of hot functions. Use any time you have a slow script, slow endpoint, or "this build takes too long."

### 3a. Text report (simplest)

```bash
# Run the workload under the profiler
node --prof dist/main.js
# ...exercise the workload, then ^C...

# Convert the binary log to a sorted text report
node --prof-process isolate-*.log > cpu-report.txt
rm isolate-*.log
```

**Read `cpu-report.txt`:** the `[Summary]` section shows time split across JIT-compiled JS, C++, GC, and the runtime. The `[Bottom up]` section lists the hottest functions — start there.

### 3b. .cpuprofile (better tooling, flame graphs)

```bash
node --cpu-prof --cpu-prof-dir=./profiles dist/main.js
# ...exercise the workload, then ^C...
# Profile saved as ./profiles/CPU.<date>.<pid>.<tid>.<seq>.cpuprofile
```

**Read:** open the `.cpuprofile` in Chrome DevTools (Performance tab → Load profile), or generate a flame graph:

```bash
npx flamebearer < ./profiles/*.cpuprofile  # produces an HTML flame graph
```

**Repo wrappers:** `scripts/perf/profile-cpu.sh` wraps both flows.

---

## 4. Heap profile + GC — "am I allocating my way to slowness?"

### 4a. Heap snapshot
```bash
node --heap-prof --heap-prof-dir=./profiles dist/main.js
# saved as ./profiles/Heap.<date>.<pid>.<tid>.<seq>.heapprofile
```
Open in Chrome DevTools → Memory → Load.

### 4b. GC tracing (no install, just log lines)
```bash
node --trace-gc dist/main.js
# Or, for more detail:
node --trace-gc --trace-gc-verbose dist/main.js
```

**Read:** frequent `Mark-Sweep` events with multi-ms pauses ⇒ you have GC pressure. Look at recent allocation hotspots (§5 chains, JSX object literals in render, etc. — see `performance.md` rule 5).

---

## 5. Database — EXPLAIN ANALYZE — "is this query actually using the index?"

The definitive answer for any "this query is slow" question. Backs up `performance.md` rule 2.

**Run via psql:**
```bash
psql "$DATABASE_URL" -c "EXPLAIN (ANALYZE, BUFFERS, VERBOSE) <your query here>;"
```

**Run via Prisma in a one-off script:**
```typescript
const result = await prisma.$queryRawUnsafe<unknown[]>(
  `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${yourQuery}`,
)
console.log(JSON.stringify(result, null, 2))
```

**Read:**
- `Seq Scan` on a large table ⇒ missing or unused index
- `actual rows` far higher than `estimated rows` ⇒ stats are stale or planner is wrong; consider `ANALYZE <table>`
- `Rows Removed by Filter:` large ⇒ filter pushed down too late; rewrite the WHERE or add an index
- `Buffers: shared read=…` high ⇒ cold cache or working set doesn't fit in RAM
- Nested Loop with high outer rows × inner cost ⇒ usually wants a hash/merge join — confirm the JOIN columns are indexed

**Repo wrapper:** `scripts/perf/explain.sh` in each NestJS service.

---

## 6. Prisma query log — "how many queries am I actually firing?"

The fastest way to catch N+1. Run a single test or a single request with logging on and count.

**One-off in a script or test:**
```typescript
import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient({
  log: [{ emit: 'event', level: 'query' }],
})

let count = 0
let totalMs = 0
prisma.$on('query', (e) => {
  count += 1
  totalMs += e.duration
  console.log(`[${e.duration}ms]`, e.query)
})

await runTheCode()
console.log(`Total queries: ${count}, total DB time: ${totalMs}ms`)
```

**Read:** if a single logical operation fires `1 + N` queries where N grows with the input, that's an N+1. Fix with `include`, `select`, or a single batched `findMany({ where: { id: { in: ids } } })`.

---

## 7. JS microbenchmarks — mitata or tinybench — "is function A faster than function B?"

For sub-millisecond, allocation-sensitive comparisons. Use only when the unit under test is genuinely hot and well-isolated; whole-app benchmarks are more honest most of the time.

**Install:**
```bash
npm i -D mitata        # or tinybench
```

**Run:**
```typescript
import { bench, run } from 'mitata'

bench('Array.includes (n=20)', () => {
  arr20.includes('target')
})
bench('Set.has (n=20)', () => {
  set20.has('target')
})

await run({ avg: true, p99: true })
```

**Read:** ops/sec with a confidence interval. Mind the JIT — mitata handles warmup, but micro-optimizations can be invalidated by inlining decisions in a different context.

---

## 8. Web Vitals + Lighthouse — "is the page actually fast for users?"

For `gp-webapp` and any user-facing surface. Headless, JSON output, scriptable.

**Install:**
```bash
npm i -g lighthouse
```

**Run against a local production build:**
```bash
npm run build && npm run start-local &
sleep 5
lighthouse http://localhost:4000/some-route \
  --output json --output html \
  --output-path ./lhr \
  --quiet --chrome-flags="--headless"
```

**Read:**
- **LCP** (Largest Contentful Paint) — target < 2.5s. Hero image or above-the-fold text.
- **INP** (Interaction to Next Paint) — target < 200ms. Long tasks blocking input.
- **CLS** (Cumulative Layout Shift) — target < 0.1. Images without dimensions, late-loading fonts.
- **TBT** (Total Blocking Time) — proxy for main-thread blocking.
- "Reduce unused JavaScript" / "Avoid enormous network payloads" — these point at bundle problems.

**Repo wrapper:** `gp-webapp/scripts/perf/lighthouse.sh`.

---

## 9. Bundle analysis — "what's bloating my JS?"

Single biggest lever for frontend perf after server response time.

**Run (Next.js, source-map-explorer):**
```bash
npm run build
npx source-map-explorer '.next/static/chunks/**/*.js' --json > bundle.json
# Human-readable HTML:
npx source-map-explorer '.next/static/chunks/**/*.js' --html bundle.html
```

**Run (@next/bundle-analyzer, alternative):**
```bash
ANALYZE=true npm run build   # needs next.config wiring; check the repo
```

**Read:** packages > 50KB gzipped per route should be challenged. Common culprits: full lodash, moment, all of MUI, charting libraries imported at the top of the route. Fix with named imports (`lodash-es`), `dynamic()`, or replacing with a lighter alternative.

**Repo wrapper:** `gp-webapp/scripts/perf/bundle-analyze.sh`.

---

## 10. Playwright tracing + perf metrics — "what happens on the user's machine, end-to-end?"

For visual perf and per-interaction breakdown. Captures network, JS, layout, paint.

```bash
npx playwright test --trace on
# Open the trace:
npx playwright show-trace test-results/**/trace.zip
```

For programmatic metrics:
```typescript
const metrics = await page.evaluate(() => JSON.stringify(performance.toJSON()))
```

---

## 11. Production telemetry (best when available)

Real users beat synthetic benchmarks. If you have access:

- **Datadog APM / Profiler** — actual p50/p95/p99 by endpoint, continuous CPU profiles in prod
- **Sentry Performance** — per-request span breakdowns with slow-query attribution
- **OpenTelemetry traces** — every NestJS service in this org ships `@opentelemetry/*` already; check the collector destination
- **CloudWatch Logs Insights** — for AWS Lambda cold start times, duration distributions

When investigating prod slowness, **always check telemetry first.** Local repro often misses cache effects, dataset shape, and concurrent load that production exposes.

---

## 12. Choosing the right tool

| Question | Tool |
|---|---|
| "Is my new code faster than the old code?" | hyperfine |
| "Is this endpoint fast enough under load?" | autocannon (single) or k6 (scenarios) |
| "Where is CPU going in this process?" | `node --prof` / `--cpu-prof` (§3) |
| "Am I allocating too much?" | `--heap-prof` + `--trace-gc` (§4) |
| "Why is this query slow?" | `EXPLAIN ANALYZE` (§5) |
| "Am I firing N+1 queries?" | Prisma query log (§6) |
| "Is array A faster than Map B at this N?" | mitata (§7) |
| "Is this page fast for users?" | Lighthouse (§8) |
| "What's making my bundle huge?" | source-map-explorer (§9) |
| "What's actually happening in prod?" | Datadog / Sentry / OTel (§11) |

---

## 13. Critic checklist

When reviewing a "performance" PR or claim, the critic should ask:

- [ ] Is there a measurement, or just an intuition?
- [ ] Was the measurement done on a representative workload, not a one-shot curl?
- [ ] Is the improvement larger than the run-to-run noise (stddev)?
- [ ] Was the hot path identified via a profile, not guessed?
- [ ] If a data structure changed, is there a microbenchmark at the real N?
- [ ] If a query changed, is there a before/after `EXPLAIN ANALYZE`?
- [ ] For frontend: is there a Lighthouse before/after, or bundle-size diff?
- [ ] Does the change add complexity disproportionate to the measured win?

Without these, "perf" PRs are guesswork. Reject them or downgrade the claim to "refactor."
