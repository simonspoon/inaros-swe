# Setup — wire in Uriel, then capture & decode the stream

Every triage playbook assumes a decoded `records.jsonl` exists. This file gets you there: **(1) add the package, (2) activate it, (3) reproduce under a lossless capture, (4) reassemble.**

## 1. Add the NuGet

```bash
dotnet add <YourMauiApp>.csproj package Uriel.Profiler
```

Drop-in and release-safe — no `#if DEBUG`, no debugger, ships in production builds.

## 2. Activate

**Preferred — explicit, reliable everywhere.** In `MauiProgram.CreateMauiApp()`:

```csharp
builder.UseUriel(o =>
{
    o.Channels            = Channels.All;   // Counters | Exceptions | Hangs | Gc
    o.CounterIntervalSec  = 1.0;            // poll cadence; higher = cheaper
    o.HangThresholdMs     = 250;            // UI stall that counts as a hang
    o.SessionId           = "triage-001";   // stamps every record's "sid" — correlate one run
});
```

Channels are flags — pay only for what you collect. `Channels.Default` = `Counters | Exceptions | Hangs` (Gc is heavier, opt in via `All`). Knobs (`UrielOptions`): `CounterIntervalSec` (1.0s), `HangThresholdMs` (250), `HangStartupGraceMs` (3000 — suppresses boot-time false hangs), `QueueCapacity` (8192 — raise if you see `seq` gaps), `MaxChunkBytes` (800 — sized for `os_log`'s ceiling), `Sentinel` (`@@URIEL@@`), `SessionId`.

**Field flip without a rebuild — best-effort.** Set env `URIEL_AUTOSTART=1|true|yes|on` to start with defaults via a module initializer. Caveat (honest): a `[ModuleInitializer]` only runs once *something* in the assembly is touched; merely referencing the package may not load it. `UseUriel(...)` is the dependable path.

**On-demand from anywhere** (no DI needed):
- `UrielProfiler.CaptureStack("label")` — snapshot the current managed stack, tagged. Plant it to localize a hotspot.
- `UrielProfiler.Mark("name", value, "note")` — drop a custom marker/metric into the same stream (frame time, "entered page X"). These become your correlation anchors.
- `UrielProfiler.IsRunning`, `UrielProfiler.Stop()` — idempotent; first `Start` wins.

## 3. Reproduce under a lossless capture

Console routing and the capture command **differ per platform**; the decode (step 4) is identical. Use a lossless pipe — dropped console lines look exactly like dropped telemetry.

| Platform | Runtime | Console → | Capture with | Never |
|---|---|---|---|---|
| Desktop / Mac Catalyst | CoreCLR | stdout | pipe directly | — (also gets all 27 EventCounters) |
| iOS sim / device | Mono | `os_log` | `simctl launch --console-pty` | `log stream` — **drops under load** |
| Android | Mono | logcat tag `DOTNET` | continuous `adb logcat` | one-shot dumps mid-run |

**Desktop (easiest, no device, full counters):**
```bash
dotnet run --project samples/Harness -c Release | python3 tools/uriel_parse.py
```

**iOS simulator** (build needs the sim RID on Intel: `-p:RuntimeIdentifier=iossimulator-x64`):
```bash
xcrun simctl boot <UDID>
: > /tmp/uriel.log
nohup xcrun simctl launch --console-pty <UDID> com.companyname.yourapp >/tmp/uriel.log 2>&1 &
# …drive the app (qorvex), then reassemble from /tmp/uriel.log
```

**Android** — the APK **must embed assemblies**, else a fast-deploy debug APK SIGABRTs (`No assemblies found … Fast Deployment`):
```bash
dotnet build <YourMauiApp>.csproj -f net9.0-android -c Debug -p:EmbedAssembliesIntoApk=true
adb install -r .../com.companyname.yourapp-Signed.apk
: > /tmp/uriel.logcat.log
adb logcat -c
nohup adb logcat -v brief > /tmp/uriel.logcat.log 2>&1 &   # continuous, lossless to file
adb shell monkey -p com.companyname.yourapp 1              # launch
# …drive the app (qorvex), then reassemble from /tmp/uriel.logcat.log
```

**Drive it with qorvex (self-driving).** Adapt the Uriel repo's `tools/qorvex_drive.sh` (iOS) / `tools/qorvex_drive_android.sh` (Android): they ensure the qorvex agent, launch under the right capture, tap the target flow by AutomationId, and dwell so periodic counters land. Key qorvex quirks they already handle — iOS: launch via `--console-pty` and do **not** `start-target` (the XCUITest agent attaches to whatever's foreground, so the pty keeps owning the lossless capture). Android: launch via `adb`, wait for `MainActivity` foreground, then retry `start-agent` until it can dump (first connect often binds the stale splash window). See the [qorvex skill](../../qorvex/SKILL.md) for driving, asserting, and screenshots.

## 4. Reassemble (identical on every platform)

`tools/uriel_parse.py` is stdlib-only. It groups chunks by `s` (seq), orders by `c[0]`, concatenates `d`, base64-decodes → one inner JSON record per line, `seq` added.

```bash
grep '@@URIEL@@' /tmp/uriel.log | python3 tools/uriel_parse.py > records.jsonl
adb logcat | python3 tools/uriel_parse.py                 # or live pipe
python3 tools/uriel_parse.py --raw < captured.log         # inner JSON verbatim
python3 tools/uriel_parse.py --sentinel '§URIEL§'         # only if a custom Sentinel was set
```

Decoded record shape:
```json
{"t":1719400000123,"k":"counter","n":"heap-bytes","v":8557240,"x":null,"sid":"triage-001","seq":2}
```
- `t` epoch ms · `k` kind (`counter|gc|exception|hang|stack|meta`) · `n` name/label · `v` number · `x` text (message / stack, when present) · `sid` session id · `seq` sequence.
- **`seq` gap = dropped chunk(s).** Uriel is drop-on-full (never blocks the app). Trends survive gaps; don't over-read a single missing sample.

Confirm collection is actually on before concluding "no issue":
```bash
jq -c 'select(.k=="meta")' records.jsonl    # session-start echoes channels=…;interval=…
```

→ Now open the playbook for your symptom: `memory-leaks.md` · `gc-pressure.md` · `ui-hangs.md` · `exceptions.md` · `startup-cpu.md`.
