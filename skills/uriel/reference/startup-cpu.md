# Playbook — slow startup & CPU / threadpool pressure

**Symptom:** the app is slow to become interactive (cold start), CPU runs hot (heat, battery), or async work stalls because the threadpool is starved.

**Available on-device? ⚠️ Partial — read this first.** The CPU/threadpool family are **CoreCLR EventCounters that never arrive on Mono** (iOS/Android). On-device you have only: **startup timing** (from `meta`/first-counter timestamps), **hangs** (UI-thread proxy for main-thread CPU), and **allocation rate** (proxy for GC-driven CPU). For *true* `cpu-usage`, `threadpool-thread-count`, `threadpool-queue-length`, run the suspect path on the **desktop Harness / Mac Catalyst (CoreCLR)** where all 27 EventCounters flow. Don't report a `cpu-usage` number on a device that never produced one.

## Signals

| Goal | Signal | Where |
|---|---|---|
| Cold-start cost | gap between `meta` `session-start` `t` and first real `counter`/heartbeat `t`; your own `Mark("app-ready")` | **everywhere** |
| Main-thread CPU bound | `k=hang` records during startup/flow (UI thread couldn't keep up) | **everywhere** |
| GC-driven CPU | `alloc-rate-bps`, `gen0-gc-count` (collections cost CPU) | **everywhere** |
| Actual CPU % | `cpu-usage` | **CoreCLR only** (Harness / Mac Catalyst) |
| Threadpool starvation | `threadpool-thread-count`, `threadpool-queue-length` rising | **CoreCLR only** |
| Lock contention | `monitor-lock-contention-count` | **CoreCLR only** |

## Triage

**Startup (on-device).** Stamp readiness in your app, then measure the gap:
```csharp
// in MauiProgram: UseUriel runs at session-start; then on first interactive frame:
UrielProfiler.Mark("app-ready");
```
```bash
# ms from profiler start to your app-ready marker
jq -s '(map(select(.k=="meta" and (.n|test("session-start")))|.t)[0]) as $s
       | (map(select(.n=="app-ready")|.t)[0]) as $r | {start:$s,ready:$r,startup_ms:($r-$s)}' records.jsonl

# hangs during the first seconds = startup work blocking the UI thread
jq -c 'select(.k=="hang")|{t,stall_ms:.v}' records.jsonl
```

**CPU / threadpool (run on the Harness, CoreCLR):**
```bash
dotnet run --project samples/Harness -c Release | python3 tools/uriel_parse.py > harness.jsonl
jq -c 'select(.k=="counter" and .n=="cpu-usage")|{t,pct:.v}' harness.jsonl
jq -c 'select(.k=="counter" and (.n=="threadpool-thread-count" or .n=="threadpool-queue-length"))|{t,n,v}' harness.jsonl
```
A rising `threadpool-queue-length` with a slowly rising `threadpool-thread-count` = **starvation** (work queued faster than threads injected — usually sync-over-async blocking pool threads).

## Likely causes in MAUI

- **Heavy `MauiProgram`/`App` ctor / `OnStart`** — eager DI graph, config parsing, DB migration, plugin init all on the startup path.
- **Synchronous I/O at launch** — reading files/prefs/network before first frame.
- **`Task.Run` blocking (`.Result`/`.Wait()`)** holding threadpool threads → starvation, cascading stalls.
- **Tight compute loops / busy-wait / polling timers** burning CPU.
- **Excessive allocation** (see `gc-pressure.md`) — GC *is* CPU cost.

## Fix patterns

- Defer non-essential startup work past first frame (lazy init, background `Task` after `app-ready`); only what's needed to render goes on the startup path.
- Make I/O async end-to-end; never block pool threads with `.Result`/`.Wait()`.
- Cache/precompute; avoid per-frame recompute; debounce polling.
- Cut allocations (→ `gc-pressure.md`) to reduce GC CPU.

## Verify

- **Startup:** re-measure the `session-start → app-ready` gap on the rebuilt artifact. Quote before/after: e.g. `startup: 2,840 ms → 1,150 ms`, and fewer/no `hang` records in the first seconds.
- **CPU/threadpool:** re-run the **Harness** and compare `cpu-usage` and `threadpool-queue-length` over the same workload. PASS = lower steady-state CPU and a queue that drains instead of growing. State explicitly that CPU numbers are from the CoreCLR Harness, not the device.
