# mesa project

Top container. Owns tasks + storyboards; deleting one cascades to both. Retiring a
project you may want back → `archive`, not `delete`.

## Commands

| Command | Purpose |
|---|---|
| `mesa project create <NAME> [--description <D>] [--path <DIR> \| --no-git \| --root-commit <SHA>]` | Create; prints full created project. |
| `mesa project list` | All projects, bare JSON array. |
| `mesa project show <ID>` | One project, full object. |
| `mesa project update <ID> <--name <N> \| --description <D> \| --path <DIR> \| --root-commit <SHA>>` | Change passed fields only; ≥1 required. |
| `mesa project resolve [PATH]` | Map a working directory (default: cwd) to its bound project via the repo's root commit. |
| `mesa project archive <ID\|NAME>` | Hide the project (and its tasks/storyboards) from unscoped views. Reversible, destroys nothing. |
| `mesa project unarchive <ID\|NAME>` | Bring an archived project back. |
| `mesa project list --include-archived` | List archived projects too (each carries `archived: true\|false`). |
| `mesa project delete <ID>` | Delete project AND all its tasks — no confirmation, cascades immediately. |

## Git binding (root_commit + local_path)

- A project may bind a **`root_commit`** — the repo's first commit, the stable identity of "this source code" across clones/worktrees/moves. Unique across projects: binding an already-bound commit → `conflict`.
- **`create` auto-binds the CWD's repo root commit** unless `--no-git` or an explicit `--root-commit`. **GOTCHA: `--path <dir>` does NOT change this** — it sets `local_path` to `<dir>` but the root commit still comes from the *cwd* repo. Creating a project for some other folder while your cwd is inside a repo that's already bound → `conflict` ("root commit … already bound to project N"). Workaround: `create --no-git` then `update --path <dir>`. (Change request filed 2026-07-04.)
- **`local_path`** = last-known working folder (machine-local convenience, anchors the Agents surface + sidebar git status). Auto-learned on create unless `--no-git`/`--root-commit`/`--path`; clear with `update --path ""`; clear the commit with `update --root-commit ""`.
- **`resolve`** is how an agent finds "the project for this checkout" instead of creating a duplicate — run it before creating a project for a repo.

## Semantics

- **update** — pass only what changes; at least one flag required. `--description ""` clears the description.
- **archive** (builds ≥ 2026-07-22) — **reach for this, not `delete`, when a project is merely finished.** Sets `archived: true`; nothing is destroyed and it is idempotent (archiving an already-archived project exits 0). Effect is a *read filter on unscoped queries only*:
  - Gone from: `project list`, unscoped `task list` / `task next`, unscoped `storyboard list`, every web-UI picker, and the todo-watcher's auto-dispatch loop (an archived project is never auto-worked).
  - **Unchanged when scoped**: `project show <ID>`, `task list <ID>`, `task next --project <ID>`, `storyboard list <ID>` return exactly what they did before archiving. Writes scoped to the id still work.
  - So: agent can't find a project it expected? Try `project list --include-archived` before concluding it was deleted.
- **delete** — still the only destructive verb, unchanged and still available to agents. Cascades to every task in the project instantly. Output echoes the deleted project plus every cascaded task in full (recoverable transcript). Want a net → `mesa backup <path>` first.

## Examples

```bash
mesa project create "Website redesign" --description "Q3 marketing site"
PID=$(mesa project create "API v2" | jq .id)   # capture id for downstream task creates
mesa project resolve ~/src/api-v2                # which project owns this checkout?
mesa project create "scratch" --no-git           # no git binding (e.g. cwd repo already bound)
mesa project update 1 --description ""           # clear description
mesa project show 1
mesa project archive "Website redesign"          # retire it; reversible, keeps every task
mesa project list --include-archived             # ...and here it is again
mesa project unarchive 1                         # bring it back
```
