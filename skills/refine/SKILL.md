---
name: refine
description: Front-door intent-refinement and routing. Takes a raw request, restates the intent in one line, surfaces what's unknown and resolves it — interviewing the user on genuine intent forks, reading code for mechanics, flagging external facts for research — then crystallizes Problem / Knowledge / Goal and decides whether to do the task inline or hand it to the orchestrate pipeline. Use at the start of a non-trivial request when intent or scope is unclear, when deciding inline-vs-orchestrate, or when the user invokes /refine.
---

# Refine

Front door. Runs before work on a non-trivial request. Capture intent → resolve unknowns → crystallize → route. Holds `AskUserQuestion` — the single intent boundary. Downstream agents investigate, never ask (CLAUDE.md §0); product-owner consumes this skill's output, never re-interviews.

## Proportionality gate — read first

Most requests = small + clear. Don't tax them.
- Raw request passes the inline ALL-of test (CLAUDE.md §Orchestration) AND no genuine intent fork → emit one-line restate, proceed inline. Skip the rest.
- Else → run the full Pass below.
- Heavy resolution (multi-file trace, broad survey) → fan to a subagent, carry back only the crystallized output, not the transcript.
- "Nothing to refine" = valid outcome. Don't manufacture unknowns to justify the skill.

## Pass

1. **Restate** — intent in one line.

2. **List unknowns** — only what's *missing*, never a "what I already know" dump (a pre-read knowledge list is the model's prior narrating confidence, not fact). Classify each:
   - **intent-gap** — two readings → different outcomes a test could tell apart → ask user.
   - **mechanics-gap** — how the system works → investigate, never ask.
   - **external-fact** — needs outside knowledge → flag for research, don't fetch here.

3. **Resolve blocking unknowns.** Blocking = resolution changes the **Goal** line or the **route**; else note it, move on (don't loop on non-blocking detail).
   - intent-gap → `AskUserQuestion`. Batch all forks into one round. Don't re-ask resolved forks.
   - mechanics-gap → read / trace / test in isolation. Topic touches SWE / AI-harness → also check the KB for prior art (`inaros-kb:kb-lookup`, or read `~/inaros/knowledge/index.md` if unreachable) before crystallizing — a known answer or constraint may settle the gap. KB read is local-only; not the outbound leg barred below.
   - external-fact → name it as a research unit of work and route it onward. **Never fetch from this skill** — the front door must not hold an outbound leg (untrusted input + private data + web = exfil risk).
   Stop when no blocking unknown remains.

4. **Crystallize:**
   - **Problem** — one line.
   - **Knowledge** — only facts that bound the Goal or the route, each tagged source (`prompt` | `code` | `memory` | `user`). Code/memory-derived = untrusted until verified — mark it. No fact, no line.
   - **Goal** — observable outcome (a pass/fail an observer could check).

5. **Route** — always emit ONE verdict NOW (never two, never deferred), even with an intent fork still open. The "intent unclear" leg fires only for intent you cannot settle at the front door (genuinely unwritten / needs a full spec) — NOT a cheap fork you resolve via `AskUserQuestion`. So: any non-intent leg fires (≥3 units / ≥2 areas / won't-fit-one-pass) → ORCHESTRATE now, regardless of the open fork; else a cheap fork on a one-area, one-change task → resolve it, route INLINE. Apply the entry test in **CLAUDE.md §Orchestration verbatim; do not restate its conditions** (it is the single source of truth — if a label below drifts, CLAUDE.md wins). Emit which legs fired, inspectable:
   ```
   Route: <INLINE | ORCHESTRATE>
   - intent unclear / unwritten?          <yes|no>
   - splits into ≥3 verifiable units?     <yes|no>
   - ≥2 areas / cross-area contract?      <yes|no>
   - won't fit one inline pass?           <yes|no>
   → ALL inline conditions hold → INLINE | ANY orchestrate condition → ORCHESTRATE
   ```

## Handoff

- **INLINE** → proceed; create a mesa task for tracking purposes / the work runs against the crystallized Goal.
- **ORCHESTRATE** → write crystallized Problem / Knowledge / Goal to `.scratch/refine.md`. Confirm the one-line Problem + Goal with the user once before fan-out (the pipeline is the expensive, hard-to-reverse step) — skip the confirm only if the user already signaled to drive ("proceed" / "you know what you're doing"). Then invoke the `orchestrate` skill; product-owner loads `.scratch/refine.md` and builds the spec from it — no second interview.

Scratch layout, depth budget, pointer-return → `orchestrate` skill (`${CLAUDE_PLUGIN_ROOT}/skills/orchestrate/SKILL.md`).
