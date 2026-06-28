# Playbook — memory leaks & unbounded growth

**Symptom:** RAM climbs over time, the OS kills the app (OOM / jetsam), or memory isn't released after navigating away from a page. The classic MAUI smell: open a page, go back, repeat — and `heap-bytes` ratchets up each cycle instead of returning to baseline.

**Available on-device?** ✅ Yes — these are GC-poll counters, present on iOS/Android (Mono) and desktop.

## Signals

| Record (`k=counter`, `n=`) | What it means | Leak tell |
|---|---|---|
| `heap-bytes` | managed heap retained (`GC.GetTotalMemory`) | rises across repeat cycles, never falls back |
| `proc-working-set` | process RSS (where reported; `0` on some Mono) | steady upward staircase |
| `gen2-gc-count` | gen2 collections (monotonic) | climbs *and yet* heap stays high → survivors are promoted, not freed |
| `gc-fragmented-bytes` | fragmented heap (CoreCLR; partial on Mono) | grows → pinning / fragmentation |
| `gc-committed-bytes` | committed to the GC (CoreCLR) | committed grows while live set should be flat |

The decisive test is **recovery after a forced settle**, not absolute size. A heap that grows during use is normal; one that won't come back down after the workload stops is the leak.

## Triage

Drive the suspect flow **N times** with qorvex (open→back ×10), then look at the heap trend per cycle:

```bash
# heap over time (epoch ms, bytes) — expect a sawtooth that returns to baseline; a leak trends up
jq -c 'select(.k=="counter" and .n=="heap-bytes")|{t,v}' records.jsonl

# first vs last heap sample — net growth across the whole run
jq -s 'map(select(.k=="counter" and .n=="heap-bytes"))|{first:.[0].v,last:.[-1].v,delta:(.[-1].v-.[0].v)}' records.jsonl

# gen2 climbing while heap stays high = promoted survivors (a real leak, not transient)
jq -c 'select(.k=="counter" and (.n=="gen2-gc-count" or .n=="heap-bytes"))|{t,n,v}' records.jsonl
```

Bracket each cycle so the per-iteration delta is unambiguous — drop a marker before and after:
```csharp
UrielProfiler.Mark("cycle-start", iteration);
// …navigate to page, render, navigate back…
GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();   // settle so retained ≠ "not yet collected"
UrielProfiler.Mark("cycle-end", iteration);
```
Then `jq` for `demo-mark`/your marker `n` to slice `heap-bytes` between brackets. Net positive delta per cycle that accumulates = leak confirmed.

## Likely causes in MAUI

- **Event handlers never unsubscribed** — `MessagingCenter`/`WeakReferenceMessenger` misuse, `+=` on a long-lived publisher (a static, a singleton service, `Connectivity`, `MainThread`) from a short-lived page/VM. The publisher keeps the subscriber alive.
- **Static / singleton holding page or view references** — caches, service locators, `Application.Current` reachable graphs.
- **Undisposed `IDisposable`** — `HttpClient` per page, streams, `CancellationTokenSource`, timers, platform handlers.
- **Page/handler not torn down** — Shell keeps pages alive; circular references through bindings or command closures capturing `this`.
- **Native↔managed bridge retention** — a managed object kept alive by a native delegate/renderer.

## Fix patterns

- Unsubscribe in `OnDisappearing`/`Dispose` for every `+=` you added; prefer weak-event or `WeakReferenceMessenger`.
- Null out / clear static caches; don't root pages from statics.
- `using`/`Dispose` every disposable; one shared `HttpClient`, not one per page.
- Break closures over `this`; unhook bindings; cancel and dispose timers/CTS on teardown.

## Verify

Re-drive the **same** N-cycle qorvex flow on the rebuilt+reinstalled artifact. PASS = `heap-bytes` returns to (≈) baseline each cycle and net delta across the run is flat; `gen2-gc-count` may still rise but heap no longer tracks it upward. Quote before/after: e.g. `Δheap ×10 cycles: 41.2 MB → 0.6 MB`.
