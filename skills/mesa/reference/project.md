# mesa project

Top container. Owns tasks + storyboards + posts; deleting one cascades to all of them.

## Commands

| Command | Purpose |
|---|---|
| `mesa project create <NAME> [--description <D>] [--path <DIR> \| --no-git \| --root-commit <SHA>]` | Create; prints full created project. |
| `mesa project list` | All projects, bare JSON array. |
| `mesa project show <ID>` | One project, full object. |
| `mesa project update <ID> <--name <N> \| --description <D> \| --path <DIR> \| --root-commit <SHA>>` | Change passed fields only; ≥1 required. |
| `mesa project resolve [PATH]` | Map a working directory (default: cwd) to its bound project via the repo's root commit. |
| `mesa project delete <ID>` | Delete project AND all its tasks — no confirmation, cascades immediately. |

## Git binding (root_commit + local_path)

- A project may bind a **`root_commit`** — the repo's first commit, the stable identity of "this source code" across clones/worktrees/moves. Unique across projects: binding an already-bound commit → `conflict`.
- **`create` auto-binds the CWD's repo root commit** unless `--no-git` or an explicit `--root-commit`. **GOTCHA: `--path <dir>` does NOT change this** — it sets `local_path` to `<dir>` but the root commit still comes from the *cwd* repo. Creating a project for some other folder while your cwd is inside a repo that's already bound → `conflict` ("root commit … already bound to project N"). Workaround: `create --no-git` then `update --path <dir>`. (Change request filed 2026-07-04.)
- **`local_path`** = last-known working folder (machine-local convenience, anchors the Agents surface + sidebar git status). Auto-learned on create unless `--no-git`/`--root-commit`/`--path`; clear with `update --path ""`; clear the commit with `update --root-commit ""`.
- **`resolve`** is how an agent finds "the project for this checkout" instead of creating a duplicate — run it before creating a project for a repo.

## Semantics

- **update** — pass only what changes; at least one flag required. `--description ""` clears the description.
- **delete** — cascades to every task in the project instantly. Output echoes the deleted project plus every cascaded task in full (recoverable transcript). Want a net → `mesa backup <path>` first.

## Examples

```bash
mesa project create "Website redesign" --description "Q3 marketing site"
PID=$(mesa project create "API v2" | jq .id)   # capture id for downstream task creates
mesa project resolve ~/src/api-v2                # which project owns this checkout?
mesa project create "scratch" --no-git           # no git binding (e.g. cwd repo already bound)
mesa project update 1 --description ""           # clear description
mesa project show 1
```
