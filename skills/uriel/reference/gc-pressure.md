# Playbook — allocation churn & GC pressure

**Symptom:** scroll/animation stutter, jank, battery drain, periodic micro-freezes. Memory may look *fine* at rest — the cost is the **rate** of allocation forcing constant gen0/gen1 collections, each a small pause. Distinct from a leak (that's retained bytes; this is throughput).

**Available on-device?** ✅ Yes — `alloc-*` and `gen0/1-gc-count` come from the GC poll sampler on iOS/Android. (CoreCLR adds `gc-heap-size`, pause-time counters in the Harness.)

## Signals

| Record (`k=counter`, `n=`) | What it means | Pressure tell |
|---|---|---|
| `alloc-rate-bps` | bytes/sec allocated (derived between polls) | sustained high during a flow that *shouldn't* allocate much |
| `alloc-total-bytes` | cumulative allocations (monotonic) | steep slope = hot allocator |
| `gen0-gc-count` | gen0 collections | climbing fast = transient garbage churn |
| `gen1-gc-count` | gen1 collections | rising = survivors escaping gen0 (mid-life pressure) |
| `k=gc` records | GC event summaries (enable `Channels.Gc`) | frequent collections clustered on a flow |

Rule of thumb: a smooth idle screen should show `alloc-rate-bps` near-flat. A spike that tracks a scroll or timer tick points straight at the hot path.

## Triage

```bash
# allocation rate over time — find the flow where it spikes
jq -c 'select(.k=="counter" and .n=="alloc-rate-bps")|{t,v}' records.jsonl

# gen0/gen1 collection counts climbing = churn (deltas matter, counts are monotonic)
jq -c 'select(.k=="counter" and (.n=="gen0-gc-count" or .n=="gen1-gc-count"))|{t,n,v}' records.jsonl

# allocation slope across the run (bytes/sec average)
jq -s 'map(select(.k=="counter" and .n=="alloc-total-bytes"))
  |{bytes:(.[-1].v-.[0].v),secs:((.[-1].t-.[0].t)/1000)}|.+{bps:(.bytes/.secs)}' records.jsonl
```

**Localize the allocator.** `alloc-rate-bps` tells you *when*, not *where*. Bracket suspects with `CaptureStack` so a `k=stack` record lands at the spike, and correlate the timestamp with qorvex `--tag`:
```csharp
UrielProfiler.Mark("scroll-start");
UrielProfiler.CaptureStack("scroll-frame");   // emits a k=stack record with the current managed stack
```
```bash
jq -r 'select(.k=="stack")|.x' records.jsonl   # the captured stacks, to read the hot call path
```

## Likely causes in MAUI

- **Per-frame / per-item allocation** — `BindableLayout`/`CollectionView` item templates allocating, converters/`StringFormat` boxing, LINQ in `OnPropertyChanged` or a scroll handler.
- **String churn** — interpolation/concat in hot bindings; build with `StringBuilder` or cache.
- **Boxing of value types** — `object` APIs, non-generic collections, struct → interface.
- **Closures & lambdas in hot paths** — captured locals allocate a closure each call; timers/animation callbacks firing often.
- **Large transient buffers** — re-allocating arrays/byte buffers each tick instead of pooling (`ArrayPool<T>`).

## Fix patterns

- Hoist allocations out of the loop/frame; cache converters and formatted strings; precompute.
- Replace LINQ-in-hot-path with explicit loops; avoid `IEnumerable` materialization per frame.
- Pool buffers (`ArrayPool<T>`), reuse `StringBuilder`, avoid boxing (generics, spans).
- Throttle/debounce high-frequency handlers; virtualize lists.

## Verify

Re-drive the same flow. PASS = `alloc-rate-bps` during the flow drops materially and `gen0`/`gen1` collection deltas fall. Quote before/after: e.g. `scroll alloc-rate: 38 MB/s → 4 MB/s; gen0 over 10s: 22 → 3`. On the desktop Harness you also get GC pause-time counters to confirm fewer/shorter pauses.
