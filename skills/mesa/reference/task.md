# mesa task

Unit of work in exactly one project (immutable after creation). Two graphs: subtask tree (`--parent`) and dependency DAG (`block` edges). Every task object carries boolean `blocked`.

## Commands

| Command | Purpose |
|---|---|
| `mesa task create --project <P> --title <TITLE> [opts]` | Create; prints full task. |
| `mesa task list [filters]` | Compact array — omits `description`, `acceptance`, `artifact`, timestamps. Filters AND together. Verify `artifact`/`acceptance` with `task show`, NOT `list` (a set field reads as absent/null here). |
| `mesa task next [--project <P>]` | Next actionable (todo + unblocked), full object. |
| `mesa task show <ID>` | Full object incl. description. |
| `mesa task update <ID> <flags>` | Change passed fields only; ≥1 required. |
| `mesa task delete <ID>` | Delete task AND all subtasks — no confirmation. |
| `mesa task block <ID> --by <BY>` | `<ID>` becomes blocked by `<BY>`. |
| `mesa task unblock <ID> --on <ON>` | Remove a blocked-by edge. |
| `mesa task events [ID]` | Status-change log, oldest first. Omit ID for all tasks. |
| `mesa task import` | Atomic graph import from JSON on stdin. |

## create / update flags

`--description <D>` · `--priority low|medium|high` (default medium) · `--tags a,b,c` · `--parent <ID>` (subtask; same project required) · `--acceptance <text>` (definition-of-done) · `--artifact <text>` (work receipt: commit SHA / PR URL / path).

update adds: `--title` · `--status todo|in_progress|done|cancelled` · `--no-parent` (detach).

- update changes only passed flags, ≥1 required. Project is immutable.
- `--description ""` / `--acceptance ""` / `--artifact ""` clear those fields.
- `--tags` **REPLACES** the full tag set; `--tags ""` clears all tags. Not additive.

### Long text from a file (`--description-file` / `--acceptance-file`)

On create AND update: `--description-file <path>` / `--acceptance-file <path>` read the field from a file (`-` = **stdin**) instead of an inline arg — content is read **verbatim**, so multi-line text with shell metacharacters (backticks, `$()`, `<>`) round-trips byte-for-byte. **This is the fix for the shell-mangling gotcha below** — prefer it over Python-subprocess for long/structured bodies.

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

## Examples

```bash
mesa task create --project 1 --title "Draft homepage copy" --priority high --tags writing,web
mesa task create --project 1 --title "Outline" --parent 7        # subtask
mesa task update 3 --status in_progress
mesa task block 3 --by 1                                 # 3 waits on 1
mesa task next --project 1
```
