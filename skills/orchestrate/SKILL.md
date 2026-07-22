---
name: orchestrate
description: How to drive the product-owner → planner → architect → engineer pipeline at scale — handoff mechanics, depth budget, context discipline (pointers not payloads), mesa-backed specs + status, .scratch/ layout, and parallel/concurrent dispatch. Use when a multi-step task spans that role pipeline, when fanning work out across many stories/epics, or when deciding how to compose those agents without blowing up context. Small task (≤ ~8 stories) → flatten, skip the epic layer.
---

# Orchestrate

How a session drives the product-owner → planner → architect → engineer pipeline at scale. Governs handoff mechanics, depth budget, context discipline. Roles defined in `${CLAUDE_PLUGIN_ROOT}/agents/`; this skill = how they compose.

Pipeline agents carry the `Skill` tool — invoke skills directly (this `orchestrate` skill, `kb-lookup`, etc.), don't only Read the file. Main loop and any orchestrator can invoke too.

## Mesa backbone

Dependency graph + status live in **mesa**, not files — so an agent queries the next-actionable story (`task next`) instead of holding or traversing the DAG in context. That server-side graph resolution is mesa's specific win; pointers-not-payloads (below) is store-agnostic — credit it there, not here. `.scratch/` holds only arch docs — engineer results are durable in mesa's own `result` field (`mesa task update --result`), not scratch: `.scratch/` is git-excluded and gets cleaned up, so long-lived narrative content never belongs there. mesa CLI details → `mesa` skill (`${CLAUDE_PLUGIN_ROOT}/skills/mesa/`).

- **Project** = the repo. Resolve: `mesa project list` → match `name` == repo basename (`basename "$(git rev-parse --show-toplevel)"`); none → `mesa project create "<basename>"`. PO does this at entry, caches `{project,spec}` in `.scratch/mesa.json`. **Worktree caveat:** inside a git worktree `--show-toplevel` = the worktree dir → basename mis-resolves (worktree name ≠ repo name). Use `basename "$(dirname "$(git rev-parse --git-common-dir)")"` there — or dispatcher pins the known project id in the PO prompt and PO skips resolution.
- **Spec** = one parent task (`tag=spec`, description = spec body). Work that *originates from an existing mesa task* (e.g. `task next` picked it) → reuse that task as the spec parent (update its description to the spec body, add `tag=spec`) — don't create a duplicate spec task beside it. **Stories** = child tasks (`--parent`), `--acceptance` = verify check, `block` edges = deps. **Epics** (large) = intermediate parent tasks (`tag=epic`).
- **Umbrella tasks** (spec, epics) set `in_progress` once children exist → excluded from `task next`, which then returns only leaf stories.
- **Work loop**: `mesa task next --project <P>` = next actionable (todo + unblocked) story → dispatch engineer. `mesa task list --project <P> --status todo --unblocked` = the concurrent batch. `.next == null` + counts (`{blocked,in_progress,todo}`) = done vs in-flight vs stuck.
- **Status = source of truth** in mesa. Engineer flips `in_progress` → `done` + writes the full narrative straight into `--result` (plus `--artifact "<sha>"` only when there's a commit/PR to point at). No ledger.
- **Agents never run `mesa serve` or `mesa delete`.** `serve` opens an outbound HTTP surface (exfil leg); `delete` cascades the whole subtree unconfirmed (wipes the backbone). Both human-operated, out-of-band.
- **Trust the cached project id, not the name.** Resolve by basename once (PO / recovery); thereafter read the `project` id from `.scratch/mesa.json`. Basename match is first-resolve only — two repos sharing a basename collide into one project.
- **`.scratch` doesn't exist in a fresh worktree.** It's git-excluded, so `EnterWorktree` (required before a background session's first edit) lands in a checkout with no `.scratch` at all — a `Write` there fails until the dir exists. `mkdir -p .scratch` and copy `mesa.json` (and any in-scope `arch.md`) over from the main checkout first, so the `{project,spec}` pointer and prior arch decisions carry into the isolated session instead of being silently lost.

## Two axes — don't conflate

- **Role pipeline: flat.** PO → planner → architect → engineer never nest *each other*. Main loop orchestrates; each role returns; main reads the artifact and dispatches the next. Nesting roles wastes depth for zero parallelism.
- **Work dispatch: hierarchical.** Many stories → orchestrators of orchestrators. Depth spent here, on fan-out capacity. Scale by widening the tree, not lengthening any context. Epic-orch layer = the `orchestrator` agent (`${CLAUDE_PLUGIN_ROOT}/agents/orchestrator.md`) — dispatch it by that name, never a generic `claude`/`general-purpose` agent (no orchestrate context, won't honor pointers/depth/mesa).

## Depth budget (floor = 5)

```
main(0)            role pipeline + epic index + epic status
  epic-orch(1)     one epic's stories + story status   [= orchestrator agent]
    engineer(2)    one story
      fan-out(3)   bug-hunt / Explore / search
```

Rules:
- Role handoff costs **0 depth** (flat, via main).
- Reserve depth 2–5 for fan-out + work dispatch.
- Small task (≤ ~8 stories) → skip epic-orch layer; main dispatches engineers directly.
- Innermost agent fails open (can't fan out, no error). Keep ≥1 depth in reserve below any agent that may delegate.
- Fan-out / search legs (depth 3): SWE / AI-harness topic → consult the KB (`inaros-kb:kb-lookup`, or read `~/inaros/knowledge/index.md`) alongside the code sweep; carry back conclusions + cite pages, don't dump. Habit inherits down the tree — each dispatcher passes it in the spawn prompt.

## Intent boundary

- Intent locked at the **front door** — the `refine` skill (main loop) captures intent and holds `AskUserQuestion`; it crystallizes Problem / Knowledge / Goal to `.scratch/refine.md` before routing here. product-owner **loads that artifact and does NOT re-interview**; main can still ask. Below the front door = mechanics-only, investigate never ask (CLAUDE.md §0).
- Deep subagents never talk to the user. Blocked-on-no-access → return `blocked`, bubble up to the front door.
- Once the user signals to drive (spec confirmed, or an explicit "proceed" / "you know what you're doing"), carry through the remaining stages and report results — don't surface next-step permission menus ("want me to hand off / kick off the engineer next?") between stages. Pause only for a genuine intent fork or a blocker, not to ask "shall I continue?".

## Context discipline — pointers, not payloads

Single biggest lever against context blowup. Heavy work isolated in the subagent's own window; the orchestrator must not re-accumulate it.

- Worker writes full result into its mesa task's `result` field (`--result-file -`), not a scratch file.
- Worker **returns one status line**, not the payload:

```
<id> <status> [note]
status ∈ pass | blocked | conflict
e.g.  04 pass
      07 blocked: missing API cred
      11 conflict: story 11 vs arch doc §3
```

- Orchestrator drops detail; status lands in mesa (task status + `result` field). Holds N one-liners, never N blobs.
- Conclusions that affect downstream work → parent writes them into its mesa task's `result` field before its own Done. Return value is disposable; the mesa task is the handoff.

## Scratch layout

Specs + status + engineer results all in mesa. `.scratch/` holds only arch docs, git-excluded. State = mesa + disk; context = working set.

```
.scratch/
  refine.md                 refine: crystallized Problem / Knowledge / Goal (front door)
  mesa.json                 {project,spec} pointer cache (product-owner)
  arch.md                   architect: cross-cutting design
  epics/
    01-<slug>/
      arch.md               architect: epic-local design (else ../arch.md)
```

No per-story directory — an engineer's full result lives in its own story task's mesa `result` field (`mesa task update <story-id> --result-file -`), not a scratch file. Small task → flatten: `.scratch/{mesa.json, arch.md}`, no `epics/`.

## Status = mesa (no ledger)

mesa task status is the source of truth; survives compaction (re-query, don't hold).
- Engineer: `in_progress` on start → `done` + `--result-file -` (full narrative, piped) on pass, plus `--artifact "<sha>"` only when there's a commit/PR to point at. `result` **is** the full result, not a pointer to one.
- Orchestrator: read state via `mesa task list/next --project <P>`; never hold the task list in context as the database — it's in mesa.
- blocked/conflict → engineer reverts the story to `todo`, writing the blocker reason directly into `--result` (no `blocked` status exists — `blocked` is edge-derived, not settable); a reverted story is thus a `todo` carrying its blocker reason in `result` that survives compaction — orchestrator reads it before re-dispatching, then re-dispatches or escalates.

## Big-task flow

Run carries through all steps in one go. refine's intent confirm (at the front door) is a **checkpoint, not a terminus** — once it routed here, don't re-pause at PO. If you must pause for confirmation, still lay out the dispatch plan in the same response: epic-orch fan-out per epic, depth levels (main 0 / epic-orch 1 / engineer 2 / fan-out 3), and the concurrency cap. A spec with no dispatch plan is half-done.

0. **refine** (front door) already ran — captured intent, wrote `.scratch/refine.md`, confirmed Problem + Goal with the user, routed here. (main loop)
1. **PO** loads `.scratch/refine.md` → expands into the spec → mesa project (resolve/create) + spec task; `.scratch/mesa.json`. No re-interview. (flat)
2. **Planner** reads spec (`mesa task show <spec-id>`). Large spec → epic parent tasks first, then **fan out per-epic planners** (depth 1) — each creates only its epic's story tasks. Avoids one planner overflowing on 100 stories. Small spec → single planner, flat story list under the spec. Sets umbrella tasks (spec, epics) `in_progress`. **Two umbrella rules the dispatch loop depends on:** (a) any TODO/parent that gains child stories MUST be flipped `in_progress` too — else `task next`/`--unblocked` returns both the parent and its leaf, dispatching the same work twice; (b) point cross-story block edges at the concrete **foundation child story**, not the umbrella (`block <dep-story> --by <foundation-story>`, not `--by <umbrella>`) — so lanes coordinate purely on leaf `done` with no umbrella-close handshake.
3. **Architect** → contracts/ADRs. Cross-cutting → `.scratch/arch.md`; epic-local → `epics/NN/arch.md`. (flat; may fan out for codebase mapping)
4. **Dispatch** — driven by `mesa task next --project <P>` (leaf stories only):
   - Each engineer flips its story `in_progress` → `done` + writes the full result into `--result` (plus `--artifact` if there's a commit SHA), returns **one status line** (`<id> <status> [note]`, status ∈ pass | blocked | conflict) — never the payload.
   - Small → main fans engineers across the unblocked batch (`task list --status todo --unblocked`, one message/multiple calls); status lands in mesa.
   - Large → main fans **one `orchestrator` agent per epic** (depth 1, the epic-orch role); each drives `task next` over its epic's stories, fans engineers (depth 2), returns one epic status line to main. Closes the epic umbrella task (`--status done`) once its stories all `done`.
   - An engineer that terminates early on a transient API error ("terminated early due to an API error" / "response stalled mid-stream") is not a `blocked`/`conflict` verdict — check the story's mesa status first (still not `done`, no commit yet): if so, resume the same agent via `SendMessage` to its returned `agentId` rather than re-dispatching a fresh one, which would duplicate work already done and lose its context.
5. Order by dependency (block edges); independent units (unblocked) run concurrent.

## Parallel writes

Concurrent engineers touching the same source → **worktree-isolate** (`isolation: worktree`). Each story's result lives in its own mesa row — never collides; source files can. Isolate only when concurrent writers overlap — it costs setup + disk.

**Expensive shared build (e.g. a 10–40 min OCCT/native compile)?** Worktree-per-agent multiplies that build — avoid it. Instead split work into **lanes by disjoint directory** (e.g. Rust kernel `cad-*` vs frontend `app/src/*`) that run concurrent on ONE tree, each lane **serial internally** on its hot files. Front-load the story that unifies the build (shared target dir) so every later build pays the native compile once.

**Lane B's *verification* may need the tree lane A is editing.** Disjoint *write* directories are not sufficient either: ask what each lane must **build** to verify, not just what it edits. A frontend lane whose acceptance is "khora against a rebuilt binary" has to compile the WHOLE tree — including the `src/` the backend lane has half-written — so it races into spurious build failures that read as its own bug, and a shared `target/` serializes them anyway. Whole-tree build + one tree = an exclusive resource, same as a device: run those lanes **serial**. Worktree-per-agent doesn't rescue this either — a fresh worktree branches from the base ref, so it silently loses the foundation commits the later stories build on (observed, mesa task 502: a frontend/Rust lane split was planned after the foundation story landed, then reversed to fully serial before dispatch, because stories 507/508 khora-verify an embedded release build).

**Exclusive external resources — worktrees don't help; serialize instead.** Disjoint files are NOT sufficient for concurrency when stories contend on a single shared *device or singleton port*: one simulator/emulator/device, or a fixed-port automation agent (khora, loki, qorvex — qorvex's agent is a singleton on `:8080`, where a second session silently cross-attaches to the WRONG device and returns plausible-but-wrong output instead of an error). Isolation can't clone the device, so run those stories **strictly serial**, even when their file ownership is perfectly disjoint and mesa says both are unblocked (observed, task 475: two qorvex automation stories plus a UI story held back one at a time). Also note **worktree isolation needs a git repo** — greenfield trees where `git init` is itself a late story get no isolation at all, so lane discipline is the only protection. Before fanning out, ask what each story needs *exclusively*, not just which files it writes.

## Cross-lane coordination

When two concurrent lanes have cross-dependencies (a story in lane B needs a story in lane A), **coordinate from the main loop, not from inside a lane-orchestrator.** A lane-orch that must block on another lane's deliverable tends to *come to rest* rather than sleep-poll for hours — and a rested background sub-agent **cannot be assumed resumable** (no `SendMessage` in some harnesses; re-spawning a fresh stateless orch is the fallback). So:
- Make dependencies leaf-to-leaf in mesa (see step 2) so unblocking is automatic on `done`.
- Drive the wait from main with a **Monitor** polling `mesa task list --status todo --unblocked` (or per-story status); on each unblock event, dispatch that engineer. This survives sub-agents resting and avoids a deadlock where lane A waits for lane B's story while lane B sits idle.
- Beware mutual cross-lane deadlock (A's last story needs B's story that needs A's earlier story): drive B's blocking story to `done` *while A is still working its independent stories*, before A reaches the dependent one.

## Concurrency

Cap ~ min(16, cores−2) concurrent per orchestrator; excess queues. Dispatch as a pipeline (drain each result as it lands) over a barrier (collect all) unless a step genuinely needs the full set.

## Recovery / compaction

State lives in mesa (task status + `result` field) plus `.scratch/` for arch docs only. After compaction or restart: re-read `.scratch/mesa.json` (missing → re-resolve project by repo basename, spec by `tag=spec`; >1 match on either → STOP, surface to the user/main, don't guess — resuming against the wrong project corrupts state), then `mesa task next --project <P>` / `task list` to resume from the first actionable story. Never hold the task list in context as the database — it's in mesa.
