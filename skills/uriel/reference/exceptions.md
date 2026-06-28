# Playbook — exceptions (first-chance storms & unhandled crashes)

**Symptom:** the app crashes, OR — more insidiously — things "just don't happen": a save silently fails, a list stays empty, a feature no-ops. Swallowed exceptions are both a correctness bug and a perf tax (throwing is expensive; a first-chance storm in a hot path quietly burns CPU).

**Available on-device?** ✅ Yes — Uriel hooks `AppDomain.CurrentDomain.FirstChanceException` and `UnhandledException` directly, so it sees exceptions on every runtime, including Mono iOS/Android.

## Signals

| Record (`k=exception`) | `n` | `v` | `x` | Meaning |
|---|---|---|---|---|
| first-chance | exception type name (e.g. `InvalidOperationException`) | `0` | `"<message>\n<stacktrace>"` | thrown — **may be caught**; fires for *every* throw, handled or not |
| unhandled | `Unhandled` | `1` | `"<FullTypeName>: <message>\n<stacktrace>"` | escaped all handlers — **this is a crash** |

Key distinction: **first-chance ≠ crash.** It fires the instant an exception is thrown, before any `catch`. A handful during startup can be normal (probing). A *flood* of the same type, or any `n="Unhandled"`, is the problem.

## Triage

```bash
# exception types by frequency — a storm is one type repeating
jq -r 'select(.k=="exception")|.n' records.jsonl | sort | uniq -c | sort -rn

# the crash(es): unhandled only, with full message+stack
jq -r 'select(.k=="exception" and .n=="Unhandled")|.x' records.jsonl

# timeline — are first-chance exceptions bursting on a specific flow?
jq -c 'select(.k=="exception")|{t,type:.n}' records.jsonl

# read the stack for a given type
jq -r 'select(.k=="exception" and .n=="NullReferenceException")|.x' records.jsonl | head -40
```

**Separate the two investigations:**
1. **`Unhandled`** → a crash. The `x` field has type, message, full stack. Fix the fault or add the missing guard. Highest priority.
2. **First-chance storm** → find the type that repeats and the flow it correlates with (match timestamps to qorvex `--tag` taps / your `Mark`s). A `try/catch` in a loop, an exception used as control flow, or a parse that always throws then falls back.

## Likely causes in MAUI

- **Exceptions as control flow** — `int.Parse` in a loop instead of `TryParse`; throwing to signal "not found".
- **Swallowed `catch {}`** — the bug is hidden but still thrown (and counted); a feature silently fails.
- **`async void` faults** — exceptions in `async void` handlers go unhandled → crash; convert to `async Task` or wrap.
- **Binding/converter exceptions** — thrown per-frame during layout, invisible without the stream.
- **Platform/permission faults** — file, network, permission denials thrown repeatedly on retry.
- **Null/serialization faults** on unexpected API shapes.

## Fix patterns

- `TryParse`/`TryGet` instead of throw-and-catch in hot paths.
- Never `catch {}` silently — log/handle, or don't catch; let unexpected faults surface.
- Make `async void` handlers `async Task` (or wrap the body in try/catch with real handling).
- Fix the binding/converter that throws; guard nulls at the boundary.
- Add the missing permission/null/format guard that caused the `Unhandled`.

## Verify

Re-drive the same flow. PASS = `n="Unhandled"` count → `0` for the crash, and the first-chance storm type drops to expected baseline. Quote before/after: e.g. `Unhandled: 1 → 0; FormatException first-chance over the flow: 214 → 0`. Confirm the `Exceptions` channel is on (`meta session-start` shows `channels=` including it) before claiming "no exceptions" — a missing signal with the channel off proves nothing.
