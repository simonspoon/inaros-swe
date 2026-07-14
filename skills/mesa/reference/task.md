# mesa task

Unit of work in exactly one project (immutable after creation). Two graphs: subtask tree (`--parent`) and dependency DAG (`block` edges). Every task object carries boolean `blocked`. `--project <P>` is a numeric id or a project name (case-insensitive; ambiguous name → `conflict`, unknown → `not_found`).

## Commands

| Command | Purpose |
|---|---|
| `mesa task create --project <P> --title <TITLE> [opts]` | Create; prints full task. |
| `mesa task list [filters]` | Compact array — omits `description`, `acceptance`, `artifact`, `result`, timestamps. Filters AND together. Verify `artifact`/`acceptance`/`result` with `task show`, NOT `list` (a set field reads as absent/null here). |
| `mesa task next [--project <P>]` | Next actionable (todo + unblocked), full object. |
| `mesa task show <ID>` | Full object incl. description. |
| `mesa task update <ID> <flags>` | Change passed fields only; ≥1 required. |
| `mesa task delete <ID>` | Delete task AND all subtasks — no confirmation. |
| `mesa task block <ID> --by <BY>` | `<ID>` becomes blocked by `<BY>`. |
| `mesa task unblock <ID> --on <ON>` | Remove a blocked-by edge. |
| `mesa task events [ID]` | Status-change log, oldest first. Omit ID for all tasks. |
| `mesa task import` | Atomic graph import from JSON on stdin. |
| `mesa task execute <ID>` | Fire the user-configured `task-execute` hook for the task (see below). |

## create / update flags

`--description <D>` · `--priority low|medium|high` (default medium) · `--tags a,b,c` · `--parent <ID>` (subtask; same project required) · `--acceptance <text>` (definition-of-done) · `--artifact <text>` (work receipt: commit SHA / PR URL / path).

update adds: `--title` · `--status todo|in_progress|done|cancelled` · `--no-parent` (detach) · `--result <text>` (final-summary prose, **update-only** — a task can't have a completion summary at creation).

- update changes only passed flags, ≥1 required. Project is immutable.
- `--description ""` / `--acceptance ""` / `--artifact ""` / `--result ""` clear those fields.
- `--tags` **REPLACES** the full tag set; `--tags ""` clears all tags. Not additive.
- `result` vs `artifact`: `artifact` is a pointer (commit SHA / PR URL / path); `result` holds the narrative itself — write the actual final summary there, e.g. `mesa task update <id> --status done --artifact <sha> --result "<summary>"`.

### Long text from a file (`--description-file` / `--acceptance-file` / `--result-file`)

On create AND update: `--description-file <path>` / `--acceptance-file <path>` read the field from a file (`-` = **stdin**) instead of an inline arg — content is read **verbatim**, so multi-line text with shell metacharacters (backticks, `$()`, `<>`) round-trips byte-for-byte. **This is the fix for the shell-mangling gotcha below** — prefer it over Python-subprocess for long/structured bodies. `--result-file` is the same mechanism, **update-only**, and is the natural way to pipe a multi-paragraph summary in: `... | mesa task update <id> --result-file -`.

- Each `*-file` flag **conflicts** with its inline twin (`--description` vs `--description-file`) → usage error, exit 2.
- Only **one** field may read `-` (stdin) per invocation → two `-` is exit 2.
- Missing/unreadable path → `validation` error, exit 1.
- On update, a `*-file` flag counts toward the ≥1-field requirement.

```bash
mesa task create --project 1 --title "Spec" --description-file ./spec.md          # from file
printf 'body with `backticks`\n' | mesa task update 7 --acceptance-file -  # from stdin
```

## list filters (combine with AND)

`--project <P>` · `--status <S>` · `--tag <T>` · `--unblocked`.

```bash
mesa task list --project 1 --status todo --unblocked   # the common "what can I pick up" query
```

## next — driving a work loop

Deterministic pick: among actionable tasks (optionally `--project`), order by priority (high>medium>low) then ascending id, return first as full object. None actionable → prints status object, exit still 0:

```json
{"next": null, "blocked": N, "in_progress": M, "todo": T}
```

Distinguishes all-done (all zero) vs work-in-flight (in_progress>0) vs stuck (blocked>0). Branch on `.next == null`, then on the counts.

## block / unblock semantics

- Blocking is **informational**: a blocked task can still be closed.
- A task is blocked while any blocker is not done/cancelled.
- Self-edges and cycles rejected → exit 1, code `cycle`. Re-adding an existing edge succeeds.
- `unblock` on a non-existent edge → error, code `not_found`.

## import — atomic task graph

One JSON document on stdin; all-or-nothing (any error → nothing created). Tasks cross-reference by client `ref` strings, resolved to real ids during import — a dependency need not know the created id. Prints created tasks as full-object array. Malformed JSON → exit 2; domain error → exit 1.

Shape:
```json
{"project": <id>, "tasks": [
  {"ref": "a", "title": "...", "description"?: "...", "acceptance"?: "...",
   "priority"?: "low|medium|high", "tags"?: ["..."], "parent"?: "<ref>", "blocked_by"?: ["<ref>", ...]}
]}
```

```bash
echo '{"project":1,"tasks":[{"ref":"a","title":"design"},{"ref":"b","title":"build","blocked_by":["a"]}]}' | mesa task import
```

## execute — fire the task-execute hook

Runs the shell command bound to `"task-execute"` in the hooks file (`hooks.json` beside the db; `MESA_HOOKS_FILE` overrides), with the full task JSON on **stdin**, `MESA_HOOK`/`MESA_TASK_ID`/`MESA_TASK_TITLE`/`MESA_PROJECT_ID`/`MESA_DB` in the env, cwd = the project's `local_path` when that folder exists. Prints a `HookRun`: `{hook, command, exit_code, stdout, stderr}` (output capped 64 KiB).

- Hook's **nonzero exit is data** (`exit_code` field), not a command failure — still exit 0. Branch on `.exit_code`, not the process exit.
- No hook configured / malformed hooks file → `validation`, exit 1. Shell cannot spawn → `unavailable`, exit 1.
- No timeout: a hook that should outlive the call must background itself (`… >/dev/null 2>&1 &`).
- Web UI equivalent: the **Execute** button in the task panel (`POST /api/tasks/{id}/execute`).

```bash
echo '{"task-execute": "echo \"picked up $MESA_TASK_ID\""}' > "$MESA_HOOKS_FILE"
mesa task execute 3 | jq .exit_code
```

## Examples

```bash
mesa task create --project 1 --title "Draft homepage copy" --priority high --tags writing,web
mesa task create --project 1 --title "Outline" --parent 7        # subtask
mesa task update 3 --status in_progress
mesa task block 3 --by 1                                 # 3 waits on 1
mesa task next --project 1
```
