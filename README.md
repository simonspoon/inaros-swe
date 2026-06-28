# inaros-swe

A [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) plugin: an opinionated software-engineering harness of **skills** and **agents**. It bundles a multi-agent orchestration pipeline, eval-driven skill tuning, an AI-expert critique panel, live QA drivers for web/desktop/mobile apps, and session retrospectives.

> **Heads up — this is personal, opinionated tooling.** It encodes one developer's workflow and taste (codified in [`CLAUDE.md`](CLAUDE.md)). Several skills drive **companion CLIs that are separate tools** (see [Requirements](#requirements)); those skills won't work without them. The rest run on Claude Code alone. Shared in case it's useful or a useful reference — not a turnkey product.

## What's inside

- **10 skills** — invocable workflows (orchestration, evals, expert consults, QA drivers, retrospectives).
- **8 agents** — specialized subagents the skills and the main loop dispatch to.
- **1 hook** — a Stop-hook code-review gate.
- **[`CLAUDE.md`](CLAUDE.md)** — the operating principles all of the above follow.

## Install

This repo is its own plugin marketplace. From inside Claude Code:

```
/plugin marketplace add simonspoon/inaros-swe
/plugin install inaros-swe@inaros-swe
```

Then restart Claude Code (or reload plugins). Skills become available as `/inaros-swe:<skill>` and agents as subagent types.

To develop locally instead, clone the repo and add it as a local marketplace:

```
/plugin marketplace add /path/to/inaros-swe
```

## Skills

| Skill | What it does | Needs |
|---|---|---|
| [`refine`](skills/refine) | Front door: restate intent → resolve unknowns → crystallize → route the task inline vs. to the pipeline. | — |
| [`orchestrate`](skills/orchestrate) | How to drive the product-owner → planner → architect → engineer pipeline at scale (handoff, depth budget, context discipline). | `mesa` |
| [`mesa`](skills/mesa) | Drive the `mesa` CLI: local-first projects, tasks with dependencies, storyboards, and a per-project bulletin board. | `mesa` |
| [`consult-ai-experts`](skills/consult-ai-experts) | Critique a skill/agent/prompt idea with a panel of 5 AI-expert personas running as parallel subagents. | — |
| [`improve-skill`](skills/improve-skill) | Eval-driven loop that improves one skill/agent: draft test cases → run via subagents → LLM-judge → smallest fix → re-test. Optional multi-model sweep. | — |
| [`retrospective`](skills/retrospective) | End-of-session review that mines the session for skill fixes, tool/config requests, and facts worth keeping. | — |
| [`khora`](skills/khora) | Drive a real Chrome browser to test a running web app — click, type, screenshot, inspect console/network. | `khora` CLI |
| [`loki`](skills/loki) | Drive a native macOS desktop app via the Accessibility API — launch, click, type, read the AX tree, screenshot. | `loki` CLI |
| [`qorvex`](skills/qorvex) | Drive a real iOS simulator, physical iOS device, or Android emulator — tap, type, swipe, read hierarchy, screenshot. | `qorvex` CLI |
| [`uriel`](skills/uriel) | Find and document runtime issues (leaks, GC pressure, UI-thread hangs) in a running .NET MAUI app. | `Uriel.Profiler` NuGet |

## Agents

| Agent | Role |
|---|---|
| [`product-owner`](agents/product-owner.md) | Builds a sliceable product-spec from refine's captured intent — without re-interviewing. |
| [`planner`](agents/planner.md) | Breaks a product-spec into independently-verifiable stories, sliced by functional area. |
| [`architect`](agents/architect.md) | Owns product design and architecture docs; defines cross-area interfaces/contracts; records decisions. |
| [`engineer`](agents/engineer.md) | Builds, debugs, reviews, and tests code against spec + architecture + story; makes the smallest verified change. |
| [`orchestrator`](agents/orchestrator.md) | Drives one epic's stories to completion — the depth-1 fan-out layer for large tasks. |
| [`consult-ai-experts` mimic](agents/expert-mimic.md) | Role-plays a named AI expert on the review panel. A critic with no tools by design. |
| [`improve-runner`](agents/improve-runner.md) | Runs a skill/agent under test on one eval scenario and reports the output. |
| [`improve-judge`](agents/improve-judge.md) | Scores one runner output against a rubric (pinned to Opus, read-only). |

## Hook

A **Stop hook** ([`hooks/stop-review-gate.sh`](hooks/stop-review-gate.sh)) acts as a code-review gate: if a turn would finish with a non-trivial, uncommitted, unreviewed diff (default ≥ 40 changed lines **or** ≥ 3 files), it prompts the agent to run `/code-review` first. It's loop-safe (prompts at most once per distinct diff), goes inert when not in a git repo or while orchestration/background work is in flight, and is tunable via `REVIEW_GATE_MIN_LINES` / `REVIEW_GATE_MIN_FILES`. To make it advisory instead of blocking, change the final `exit 2` to `exit 0`.

## Philosophy

The plugin is built around a few principles, spelled out in [`CLAUDE.md`](CLAUDE.md):

- **Ask intent, investigate mechanics.** Ask the user only when two readings would produce genuinely different results; otherwise read the code.
- **Understand before changing; keep it simple; surgical diffs.** Smallest change that solves the stated problem, touching only what's required.
- **Goal-driven execution.** Decide the verification up front, then work until it passes.
- **Orchestrate when it's big.** A clear entry test routes work between a single inline pass and the full product-owner → planner → architect → engineer pipeline.

## Requirements

- **[Claude Code](https://docs.claude.com/en/docs/claude-code/overview)** — a recent version with plugin support.
- **bash + git** — for the Stop hook. `jq` and the `mesa` CLI are optional; without them the hook simply skips its orchestration-aware checks.
- **Companion CLIs**, only for the skills that name them above:
  - [`mesa`](skills/mesa) (used by `mesa` and `orchestrate`), `khora`, `loki`, and `qorvex` — separate command-line tools that must be installed and on your `PATH`.
  - `Uriel.Profiler` — a NuGet package added to the .NET MAUI app under test.

  These companion tools are not included in this repo. The skills that don't list a dependency (`refine`, `orchestrate`'s guidance, `consult-ai-experts`, `improve-skill`, `retrospective`) work with Claude Code alone.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). In short: it's opinionated tooling — open an issue before a large PR, keep diffs surgical, and match the existing register.

## License

[MIT](LICENSE) © Simon Spoon
