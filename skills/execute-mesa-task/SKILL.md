---
name: execute-mesa-task
description: Execute a mesa task end-to-end from a task id — fetch task info, route it through refine, work to completion, commit to main, run retrospective, auto-apply high-confidence findings, clean up temp files/worktrees, then summarize. Use when the user invokes /execute-mesa-task <task-id> or asks to "run/execute/pick up mesa task N end-to-end".
---

# Execute Mesa Task

Glue skill: chains task-pickup → refine → ship → retro → cleanup into one command. `$ARGUMENTS` = task id. Doesn't replace `refine`/`orchestrate`/`retrospective` — invokes them.

## Steps

1. **Fetch** — `mesa task show <id>`. No id given → `mesa task next --project <P>` (P = resolve by repo basename, per `orchestrate` skill's mesa-backbone section). Task missing / already done / blocked → stop, report, don't guess.
2. **Pick up** — flip `in_progress` immediately. No dispatched engineer here to do this later — this skill IS the pickup.
3. **Refine** — pass the task's title+description as the raw request to the `refine` skill. Refine restates intent, resolves unknowns, routes INLINE or ORCHESTRATE. This skill does NOT re-interview — refine alone owns `AskUserQuestion`.
4. **Work** — inline pass or full pipeline, per refine's route. Verify per CLAUDE.md §4 (test / typecheck / run+observe / diff-vs-criteria — strongest the task allows).
5. **Complete** — mesa task → `done` + `--artifact` (result path or commit SHA — one value).
6. **Commit to main** — direct commit, no PR. Matches this task's own instruction and the user's standing git preference (commit direct to main). This supersedes the background-job default of isolate→PR→ask for *this* explicit instruction only — don't silently fall back to opening a PR, and don't generalize the skip to unrelated commits.
7. **Retrospective** — invoke `retrospective` skill against this session (task 1–6 + this skill's own run).
8. **Auto-apply high-confidence findings** — the one place this skill overrides `retrospective`'s default report-only gate, per this workflow's explicit charter. High-confidence = cites a concrete moment from this run AND has a low-blast-radius owner:
   - (a) skill wording fix → edit the named `SKILL.md` directly.
   - (c) memory fact → write it (standard memory protocol).
   - (d) KB-worthy → run `/kb-capture`.
   - (e) tool change request → `mesa inbox add`.
   - (b) config / permission / hook change → never auto-apply, even here — `retrospective`'s hard rule survives this override. Print the command for the user.
   No cited moment, or genuinely speculative → leave in the report, don't apply.
9. **Cleanup** — remove this run's temp files; if a worktree was created for the task, verify the commit landed on `main` FIRST (`git log --oneline main..<worktree-branch>` empty, or `git log -1 main` shows the SHA) — the worktree branch is the only copy of the commit until merged, and `ExitWorktree`/`git branch -d` deletes it irreversibly. Only then `ExitWorktree` (`remove`); `keep` only if the task ended blocked/unfinished.
10. **Summarize** — one short report: task id/title, route taken (INLINE/ORCHESTRATE), what shipped (commit SHA), findings applied vs left for the user, cleanup done.

## Notes

- Steps 6 and 8 each deliberately break another skill's default (background-job PR-first; retrospective's report-only). Both breaks are scoped to this skill's own explicit charter — don't carry "skip PR" or "auto-apply" into other, unrelated invocations of refine/retrospective.
- Task turns out too large for one inline pass → follow refine's own ORCHESTRATE route. This skill doesn't force inline; it forces nothing beyond the chaining.
