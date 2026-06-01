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

## At a glance: tool readiness

Use this table to pick a tool that fits the situation you're actually in (no running server, no global install, DB in Docker, etc.) without having to read each section first.

The **Agent runtime** column tells an AI agent reviewing a PR what it can realistically run unattended:

- **GREEN** — Agent can run it unattended if the basic env is present.
- **YELLOW** — Needs a long-running service (built artifact, dev server, prod-like server) the agent should not start on its own.
- **RED** — Needs human credentials (Datadog/Sentry/prod APM/observability backends).

| § | Tool | Prereqs | Agent runtime |
|---|---|---|---|
| §0 | `hyperfine` | Binary on PATH (or `cargo install hyperfine`); two runnable commands to compare. | GREEN if installed; otherwise SKIP — heavy install. |
| §1 | `autocannon` | Target HTTP server up; `autocannon` on PATH OR fallback to `npx --yes autocannon`. | YELLOW — needs the dev/prod server running. |
| §2 | `k6` | `k6` on PATH; scenario file (`perf/*.ts`); target server up. | YELLOW — needs the server. |
| §3 | `node --prof`, `--cpu-prof` | `node` on PATH; direct `node` invocation of the workload (NOT via `npm run` / `nest start` — see §3b gotcha). | GREEN for any script you can run directly. |
| §4 | `--heap-prof`, `--trace-gc` | Same as §3. | GREEN. |
| §5 | `EXPLAIN ANALYZE` | A Postgres connection. EITHER `psql` on PATH AND `DATABASE_URL` resolvable, OR a running container you can `docker exec ... psql` into. | GREEN when DB is up locally. |
| §6 | Prisma query log | A running script/test that can construct a `PrismaClient`; usual Node + Prisma deps installed. | GREEN. |
| §7 | `mitata` / `tinybench` | `npm install -D mitata` in the target repo; the function under test importable from a script. | GREEN. |
| §8 | Lighthouse | Built production frontend listening on a URL; `lighthouse` on PATH OR `npx --yes lighthouse`. | YELLOW — `npm run build && npm run start-local` needed first. |
| §9 | `source-map-explorer` / `@next/bundle-analyzer` | Built artifacts in `.next/static/`; `productionBrowserSourceMaps: true` in `next.config.ts`. No global install — `npx` always works. | YELLOW — needs a build, but no server. |
| §10 | Playwright | Playwright installed (`npx playwright install`); test or page-evaluate target. | YELLOW — usually needs the app up. |
| §11 | Datadog / Sentry / OTel | Org credentials, cluster access, IDP. | RED — never agent-unattended in a dev review. |

> **For agents in a fresh git worktree** there's an extra setup tax — see §11.6 ("Agents in fresh worktrees") before assuming any of the YELLOW/GREEN tools will work first-try.

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
# Use --prepare to switch branches BEFORE each timed run.
# Do NOT use 'git stash && cmd' / 'git stash pop && cmd' as the two commands —
# hyperfine runs them round-robin and the stash stack desyncs after the first
# pair, silently benchmarking the same code on every subsequent iteration.
hyperfine --warmup 3 --runs 20 \
  --prepare 'git checkout main'      'npm run my-script' \
  --prepare 'git checkout my-branch' 'npm run my-script'
```

Alternative: use `git worktree add ../old-version <commit>` for two independent directories, then `hyperfine '(cd ../old-version && npm run my-script)' '(cd . && npm run my-script)'`. This avoids checking out the other branch in your active working tree at all.

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
# or, no install needed:
npx --yes autocannon ...
```

**Requires:** the target HTTP server already listening on the URL (start `npm run start:dev` first). Without that you'll get a `0/0/0 reqs/sec` table with one connection error.

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
# --compatibility-mode=extended is required for .ts scenarios (default is `base` = ES5.1+ JS only).
k6 run --compatibility-mode=extended --summary-trend-stats "avg,med,p(50),p(95),p(99),min,max" perf/mixed.ts
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
npx speedscope ./profiles/*.cpuprofile   # opens an interactive flame graph in the browser
```

> `speedscope` accepts `.cpuprofile` natively. `flamebearer` does not — it only takes preprocessed V8 isolate logs (the output of `node --prof-process --preprocess -j`), and its own README now points users at speedscope as the replacement.

> **Gotcha — `--cpu-prof` cannot be set via `NODE_OPTIONS`.** Node 18+ rejects it: `node: --cpu-prof is not allowed in NODE_OPTIONS`. You must pass the flag on the `node` command line directly. That means:
>
> - For a built app: `node --cpu-prof --cpu-prof-dir=./profiles dist/main.js` ✓
> - For `npm run start:prod`, `nest start`, `next start`: **you cannot just `export NODE_OPTIONS`.** Either profile the underlying built JS directly (`dist/main.js`, `.next/standalone/server.js`), or temporarily edit the `package.json` script to inject the flag (`"start:prod:profile": "node --cpu-prof --cpu-prof-dir=./profiles dist/main.js"`).
> - The same restriction applies to `--heap-prof`. `--prof` and `--trace-gc` ARE allowed in `NODE_OPTIONS`.

**Repo wrappers:** `scripts/perf/profile-cpu.sh` wraps the direct-`node` flow.

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

**Requires:** a Postgres connection. If `psql` isn't on your PATH but your DB is in Docker (common dev setup), `docker exec <container> psql ...` works identically — see §11.5 Fallback patterns. If you're in a fresh git worktree, `.env` is likely missing — see §11.6.

**Run via psql:**
```bash
psql "$DATABASE_URL" -c "EXPLAIN (ANALYZE, BUFFERS, VERBOSE) <your query here>;"
```

**Run via docker exec (when host `psql` isn't installed):**
```bash
docker exec -i goodparty-postgres psql -U postgres -d gpdb \
  -c "EXPLAIN (ANALYZE, BUFFERS) <your query here>;"
```

**Run via Prisma in a one-off script:**
```typescript
// Parameterize every dynamic value — $1, $2, ... — never interpolate into
// the SQL string. The static EXPLAIN prefix is fine; the query body must be
// a fixed string literal you wrote, and any inputs become bound parameters.
const result = await prisma.$queryRawUnsafe<unknown[]>(
  'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM "User" WHERE id = $1',
  userId,
)
console.log(JSON.stringify(result, null, 2))
```

> **Do not** template-interpolate a query string into `$queryRawUnsafe` (`` `EXPLAIN ... ${yourQuery}` ``). That's the exact pattern `security.md` rule §1 flags as SQL injection. If you need to compose a query at runtime from user input, build it with `Prisma.sql\`...\`` and `prisma.$queryRaw` — both are parameterized at the driver level.

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
# or, no install needed:
npx --yes lighthouse ...
```

**Requires:** a built **production** server listening on the URL — not `npm run dev`. Build and start it first (`npm run build && npm run start-local &`). Lighthouse against a dev server gives meaningless numbers because dev mode disables minification and bundle splitting.

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

**Requires:** built artifacts in `.next/static/`. `productionBrowserSourceMaps: true` must be set in `next.config.ts` (this repo already has it) — otherwise the explorer can't map chunks back to source modules. No global install needed; `npx` is fine.

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
// performance.toJSON() is a non-standard V8 convenience that returns ONLY
// timeOrigin + timing — it does NOT include paint/navigation/layout entries
// despite the convenient name. Use the entry-type APIs instead, and don't
// JSON.stringify inside page.evaluate — Playwright structured-clones the
// return value for you.
const metrics = await page.evaluate(() => ({
  navigation: performance.getEntriesByType('navigation')[0]?.toJSON(),
  paint:      performance.getEntriesByType('paint').map((e) => e.toJSON()),
  // Add 'resource' for per-asset timing, 'largest-contentful-paint' for LCP, etc.
}))
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

## 11.5. Fallback patterns when your environment is missing the obvious

Plenty of environments are missing `brew`, missing global node tooling, run Postgres in a container, or don't have direct `psql` on PATH. Most of the tools above have a workaround that costs ~30s to discover the hard way.

| Tool | Without a global install | When the dep is in Docker |
|---|---|---|
| `autocannon` | `npx --yes autocannon -c 10 -d 30 http://...` | — |
| `lighthouse` | `npx --yes lighthouse http://... --output html --output-path ./lhr` | — |
| `psql` | (rarely installed without effort) | `docker exec -i <container> psql -U <user> -d <db> -c "<query>"` |
| `hyperfine` | `cargo install hyperfine`, or skip — there's no comparable one-line install elsewhere | — |
| `source-map-explorer` | `npx --yes source-map-explorer '.next/static/chunks/**/*.js' --html out.html` | — |
| `k6` | (binary install required — no npx equivalent) | `docker run --rm -i grafana/k6 run --compatibility-mode=extended - <perf/scenario.ts` |
| `node --cpu-prof` | Already shipped with `node`. **Do not** try to inject via `NODE_OPTIONS` — see §3b. | — |
| Prisma query log | None — has to run as part of the app's own process. | — |

**Install hints by platform** (use whichever applies):

| Tool | macOS | Debian/Ubuntu | Fedora/RHEL |
|---|---|---|---|
| `psql` (`libpq`) | `brew install libpq` | `apt install postgresql-client` | `dnf install postgresql` |
| `hyperfine` | `brew install hyperfine` | `cargo install hyperfine` | `cargo install hyperfine` |
| `k6` | `brew install k6` | `apt install k6` (Grafana apt repo) | (use Docker) |
| `lighthouse` (preferred: `npx`) | `npm i -g lighthouse` | `npm i -g lighthouse` | `npm i -g lighthouse` |
| `autocannon` (preferred: `npx`) | `npm i -g autocannon` | `npm i -g autocannon` | `npm i -g autocannon` |

---

## 11.6. Agents in fresh worktrees

If an AI agent is reviewing or measuring inside a `git worktree`, two things bite *before* any of the tools above:

1. **`.env` is usually NOT in the worktree.** It's `.gitignore`d, so a `worktree add` produces a checkout without it. To find one:
   ```bash
   # Locate the parent (superproject) worktree:
   git worktree list | head -1
   # Or, from a submodule:
   git rev-parse --show-superproject-working-tree
   # Then copy or symlink:
   cp ../<parent-name>/.env .
   # Or set DATABASE_URL inline:
   export DATABASE_URL="$(grep '^DATABASE_URL=' ../<parent-name>/.env | cut -d= -f2- | tr -d '\"')"
   ```
2. **Submodules need initialization.** The `ai-rules/` submodule (containing this file) is not auto-checked-out in a new worktree:
   ```bash
   git submodule update --init --recursive
   ```
   And the submodule's commit pointer may pre-date a recent rule change — if `ai-rules/performance.md` looks stale or is missing, check it out at the branch you expect:
   ```bash
   (cd ai-rules && git fetch && git checkout origin/main)
   ```
3. **`node_modules` is per-worktree.** Anything that runs Node will fail without `npm install` first.

A repo-shipped `scripts/perf/setup-check.sh` (when present) is the fastest way to verify all of the above in one shot — run it first.

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
