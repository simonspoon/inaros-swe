# Playbook — UI-thread hangs (jank / ANR / beachball)

**Symptom:** the app freezes on a tap or transition; Android shows "Application Not Responding", iOS just stops responding. The UI thread is blocked doing work it shouldn't.

**Available on-device?** ✅ Yes — Uriel's hang watchdog round-trips a heartbeat through the MAUI main thread; if the pong doesn't return within `HangThresholdMs`, it emits a `hang` record. Works on every target (it's a timer + `MainThread.BeginInvokeOnMainThread`, not a runtime counter).

## Signals

| Record | Field | Meaning |
|---|---|---|
| `k=hang` | `n="ui-stall"` | the UI thread missed its heartbeat |
| | `v` | **observed stall in ms** — how long the main thread was unresponsive |
| | `x` | `"UI thread did not service heartbeat within threshold"` |

Tuning (`UrielOptions`): `HangThresholdMs` (default 250 — lower to catch jank, raise to only catch egregious freezes), `HangStartupGraceMs` (default 3000 — suppresses false hangs while the UI thread is busy booting). The watchdog re-arms after each report, so one sustained freeze = one record, not a spam storm.

## Triage

```bash
# every UI stall, worst first — v is the freeze duration in ms
jq -c 'select(.k=="hang")|{t,stall_ms:.v}' records.jsonl | sort -t: -k2 -rn

# count + max stall
jq -s 'map(select(.k=="hang").v)|{count:length,max_ms:(max//0)}' records.jsonl
```

**Localize.** The watchdog reports *latency, not a stack* — a cross-thread managed stack walk isn't available on mobile. So you correlate **timestamp → action**:
- qorvex tags every tap (`--tag btnCheckout`); match the `hang.t` to the tap that preceded it.
- Plant `UrielProfiler.Mark("before-X")` / `Mark("after-X")` around suspect synchronous work; a `hang` between the marks names the culprit.
- The stall magnitude (`v`) tells severity: ~250–500 ms = jank; >5 s on Android risks a system ANR kill.

```bash
# interleave marks + hangs on one timeline to see what ran when it froze
jq -c 'select(.k=="hang" or (.k=="counter" and (.n|startswith("before-") or startswith("after-"))))|{t,k,n,v}' records.jsonl
```

## Likely causes in MAUI

- **Synchronous I/O on the UI thread** — `HttpClient` `.Result`/`.Wait()`, file/DB reads, `Task.Run(...).Result` (sync-over-async deadlock risk).
- **Heavy compute in an event handler** — parsing, image decode/resize, large LINQ, JSON deserialization on tap.
- **Big layout/measure passes** — inflating a huge view tree, non-virtualized lists, deep nested layouts in `OnAppearing`.
- **`Thread.Sleep` / blocking locks on the main thread.**
- **`async void` swallowing the await** so work effectively runs sync, or `.ConfigureAwait(true)` forcing a continuation back onto a busy UI thread.

## Fix patterns

- Move work off the UI thread: `await Task.Run(...)`, async APIs end-to-end, `ConfigureAwait(false)` in library code.
- Marshal only the final UI update back via `MainThread.BeginInvokeOnMainThread`.
- Defer/await heavy `OnAppearing` work; show a spinner; virtualize lists; lazy-load.
- Never block: replace `.Result`/`.Wait()`/`Thread.Sleep` with `await`.

## Verify

Re-drive the same tap/flow. PASS = **no `hang` record** at that action (or stall `v` below threshold). Quote before/after: e.g. `checkout tap: 1 hang @ 612 ms → 0 hangs`. If you lowered `HangThresholdMs` to catch jank during triage, keep the same threshold for the verify run so the comparison is apples-to-apples.
