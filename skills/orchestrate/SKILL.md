---
name: orchestrate
description: How to drive the product-owner → planner → architect → engineer pipeline at scale — handoff mechanics, depth budget, context discipline (pointers not payloads), mesa-backed specs + status, .scratch/ layout, and parallel/concurrent dispatch. Use when a multi-step task spans that role pipeline, when fanning work out across many stories/epics, or when deciding how to compose those agents without blowing up context. Small task (≤ ~8 stories) → flatten, skip the epic layer.
---

# Orchestrate

How a session drives the product-owner → planner → architect → engineer pipeline at scale. Governs handoff mechanics, depth budget, context discipline. Roles defined in `${CLAUDE_PLUGIN_ROOT}/agents/`; this skill = how they compose.

Pipeline agents carry the `Skill` tool — invoke skills directly (this `orchestrate` skill, `kb-lookup`, etc.), don't only Read the file. Main loop and any orchestrator can invoke too.

## Mesa backbone

Specs + status live in **mesa**, not files. `.scratch/` holds only arch docs + engineer results. mesa CLI details → `mesa` skill (`${CLAUDE_PLUGIN_ROOT}/skills/mesa/`).

- **Project** = the repo. Resolve: `mesa project list` → match `name` == repo basename (`basename "$(git rev-parse --show-toplevel)"`); none → `mesa project create "<basename>"`. PO does this at entry, caches `{project,spec}` in `.scratch/mesa.json`.
- **Spec** = one parent task (`tag=spec`, description = spec body). **Stories** = child tasks (`--parent`), `--acceptance` = verify check, `block` edges = deps. **Epics** (large) = intermediate parent tasks (`tag=epic`).
- **Umbrella tasks** (spec, epics) set `in_progress` once children exist → excluded from `task next`, which then returns only leaf stories.
- **Work loop**: `mesa task next --project <P>` = next actionable (todo + unblocked) story → dispatch engineer. `mesa task list --project <P> --status todo --unblocked` = the concurrent batch. `.next == null` + counts (`{blocked,in_progress,todo}`) = done vs in-flight vs stuck.
- **Status = source of truth** in mesa. Engineer flips `in_progress` → `done` + `--artifact "<result.md | SHA>"`. No ledger.

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

## Intent boundary

- Intent locked at **depth 1 only** — product-owner holds `AskUserQuestion`; main can ask. Below depth 1 = mechanics-only, investigate never ask (CLAUDE.md §0).
- Deep subagents never talk to the user. Blocked-on-no-access → return `blocked`, bubble up to depth 1.
- Once the user signals to drive (spec confirmed, or an explicit "proceed" / "you know what you're doing"), carry through the remaining stages and report results — don't surface next-step permission menus ("want me to hand off / kick off the engineer next?") between stages. Pause only for a genuine intent fork or a blocker, not to ask "shall I continue?".

## Context discipline — pointers, not payloads

Single biggest lever against context blowup. Heavy work isolated in the subagent's own window; the orchestrator must not re-accumulate it.

- Worker writes full result to its artifact file.
- Worker **returns one status line**, not the payload:

```
<id> <status> [note]
status ∈ pass | blocked | conflict
e.g.  04 pass
      07 blocked: missing API cred
      11 conflict: story 11 vs arch doc §3
```

- Orchestrator drops detail; status lands in mesa (task status + `--artifact` pointer). Holds N one-liners, never N blobs.
- Conclusions that affect a downstream artifact → parent writes them into the artifact before its own Done. Return value is disposable; the file (or mesa task) is the handoff.

## Scratch layout

Specs + status in mesa. `.scratch/` holds the rest, git-excluded. State = mesa + disk; context = working set.

```
.scratch/
  mesa.json                 {project,spec} pointer cache (product-owner)
  arch.md                   architect: cross-cutting design
  epics/
    01-<slug>/
      arch.md               architect: epic-local design (else ../arch.md)
      stories/
        <story-task-id>/
          result.md         engineer: full result
```

Story dirs key off the mesa story task id. Small task → flatten: `.scratch/{mesa.json, arch.md, stories/<id>/result.md}`, no `epics/`.

## Status = mesa (no ledger)

mesa task status is the source of truth; survives compaction (re-query, don't hold).
- Engineer: `in_progress` on start → `done` + `--artifact "<result.md path | commit SHA>"` on pass. `--artifact` is the pointer to the full result.
- Orchestrator: read state via `mesa task list/next --project <P>`; never hold the task list in context as the database — it's in mesa.
- blocked/conflict → task left not-done; engineer's returned status line carries the note; orchestrator re-dispatches or escalates.

## Big-task flow

Run carries through all 5 steps in one go. The PO "User confirms" is a **checkpoint, not a terminus** — do not stop there. If you must pause for confirmation, still lay out the dispatch plan in the same response: epic-orch fan-out per epic, depth levels (main 0 / epic-orch 1 / engineer 2 / fan-out 3), and the concurrency cap. A spec with no dispatch plan is half-done.

1. **PO** → mesa project (resolve/create) + spec task; `.scratch/mesa.json`. User confirms. (flat)
2. **Planner** reads spec (`mesa task show <spec-id>`). Large spec → epic parent tasks first, then **fan out per-epic planners** (depth 1) — each creates only its epic's story tasks. Avoids one planner overflowing on 100 stories. Small spec → single planner, flat story list under the spec. Sets umbrella tasks (spec, epics) `in_progress`.
3. **Architect** → contracts/ADRs. Cross-cutting → `.scratch/arch.md`; epic-local → `epics/NN/arch.md`. (flat; may fan out for codebase mapping)
4. **Dispatch** — driven by `mesa task next --project <P>` (leaf stories only):
   - Each engineer flips its story `in_progress` → `done` + `--artifact`, writes full result to `result.md`, returns **one status line** (`<id> <status> [note]`, status ∈ pass | blocked | conflict) — never the payload.
   - Small → main fans engineers across the unblocked batch (`task list --status todo --unblocked`, one message/multiple calls); status lands in mesa.
   - Large → main fans **one `orchestrator` agent per epic** (depth 1, the epic-orch role); each drives `task next` over its epic's stories, fans engineers (depth 2), returns one epic status line to main. Closes the epic umbrella task (`--status done`) once its stories all `done`.
5. Order by dependency (block edges); independent units (unblocked) run concurrent.

## Parallel writes

Concurrent engineers touching the same source → **worktree-isolate** (`isolation: worktree`). Per-story `result.md` paths never collide; source files can. Isolate only when concurrent writers overlap — it costs setup + disk.

## Concurrency

Cap ~ min(16, cores−2) concurrent per orchestrator; excess queues. Dispatch as a pipeline (drain each result as it lands) over a barrier (collect all) unless a step genuinely needs the full set.

## Recovery / compaction

State lives in mesa (+ `.scratch/` for arch/results). After compaction or restart: re-read `.scratch/mesa.json` (missing → re-resolve project by repo basename, spec by `tag=spec`), then `mesa task next --project <P>` / `task list` to resume from the first actionable story. Never hold the task list in context as the database — it's in mesa.
