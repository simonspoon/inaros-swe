---
name: orchestrate
description: How to drive the product-owner → planner → architect → engineer pipeline at scale — handoff mechanics, depth budget, context discipline (pointers not payloads), .scratch/ layout, ledger format, and parallel/concurrent dispatch. Use when a multi-step task spans that role pipeline, when fanning work out across many stories/epics, or when deciding how to compose those agents without blowing up context. Small task (≤ ~8 stories) → flatten, skip the epic layer.
---

# Orchestrate

How a session drives the product-owner → planner → architect → engineer pipeline at scale. Governs handoff mechanics, depth budget, context discipline. Roles defined in `${CLAUDE_PLUGIN_ROOT}/agents/`; this skill = how they compose.

Pipeline agents carry the `Skill` tool — invoke skills directly (this `orchestrate` skill, `kb-lookup`, etc.), don't only Read the file. Main loop and any orchestrator can invoke too.

## Two axes — don't conflate

- **Role pipeline: flat.** PO → planner → architect → engineer never nest *each other*. Main loop orchestrates; each role returns; main reads the artifact and dispatches the next. Nesting roles wastes depth for zero parallelism.
- **Work dispatch: hierarchical.** Many stories → orchestrators of orchestrators. Depth spent here, on fan-out capacity. Scale by widening the tree, not lengthening any context.

## Depth budget (floor = 5)

```
main(0)            role pipeline + epic index + epic status
  epic-orch(1)     one epic's stories + story status
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

- Orchestrator records the line to its ledger, drops detail. Holds N one-liners, never N blobs.
- Conclusions that affect a downstream artifact → parent writes them into the artifact before its own Done. Return value is disposable; the file is the handoff.

## Scratch layout

All planning state on disk, git-excluded. State = disk; context = working set.

```
.scratch/
  product-spec.md           product-owner
  ledger.md                 top-level: one line per epic
  epics/
    01-<slug>/
      stories.md            this epic's story index
      ledger.md             one line per story in epic
      arch.md               architect (per-epic) or ../arch.md if cross-cutting
      stories/
        01/
          story.md          planner
          result.md         engineer: full result
```

Small task → flatten: `.scratch/{product-spec.md, stories/, ledger.md}`, no `epics/`.

## Ledger format

Append-only. One line per unit. Source of truth for status; survives compaction (re-read, don't hold).

```
<id>  <status>  <pointer>
01    pass      epics/01-auth/stories/01/result.md
02    blocked   epics/01-auth/stories/02/result.md
```

## Big-task flow

1. **PO** → `product-spec.md`. User confirms. (flat)
2. **Planner**, large spec → decompose to epics first (`epics/*/`), then **fan out per-epic planners** (depth 1) — each emits only its epic's `stories.md`. Avoids one planner overflowing on 100 stories. Small spec → single planner, flat story list.
3. **Architect** → contracts/ADRs. Cross-cutting → `.scratch/arch.md`; epic-local → `epics/NN/arch.md`. (flat; may fan out for codebase mapping)
4. **Dispatch:**
   - Small → main fans engineers across independent stories (one message, multiple calls), drains pass/fail to `ledger.md`.
   - Large → main fans **one epic-orch per epic** (depth 1); each epic-orch fans engineers (depth 2) over its stories, drains to its `epics/NN/ledger.md`, returns one epic status line to main's `ledger.md`.
5. Order by dependency (planner-stated); independent units run concurrent.

## Parallel writes

Concurrent engineers touching the same source → **worktree-isolate** (`isolation: worktree`). Per-story `result.md` paths never collide; source files can. Isolate only when concurrent writers overlap — it costs setup + disk.

## Concurrency

Cap ~ min(16, cores−2) concurrent per orchestrator; excess queues. Dispatch as a pipeline (drain each result as it lands) over a barrier (collect all) unless a step genuinely needs the full set.

## Recovery / compaction

State lives in `.scratch/`. After compaction or restart: re-read `ledger.md` + epic ledgers, resume from first non-`pass` unit. Never hold the ledger in context as the database — it's on disk.
