# mesa storyboard

Freeform visual canvas in one project (immutable after creation): frames (cards) + directed edges. Not a dependency graph — cycles allowed. Render via the web UI (`reference/serve.md`).

Sub-groups: storyboard itself, `frame`, `edge`.

## storyboard

| Command | Purpose |
|---|---|
| `mesa storyboard create --project <P> <TITLE> [--description <D>] [--author <A>]` | Create; full object. |
| `mesa storyboard list [--project <P>]` | Array, no frames/edges — use `show` for those. |
| `mesa storyboard show <ID>` | Full contents: `{storyboard, frames, edges}`. |
| `mesa storyboard update <ID> <--title <T> \| --description <D>> [--author <A>]` | ≥1 field; project + author immutable. |
| `mesa storyboard delete <ID>` | Delete board AND all frames, edges, history — no confirmation. |
| `mesa storyboard events <ID>` | Change history, oldest first (see below). |

## frame (cards)

| Command | Purpose |
|---|---|
| `mesa storyboard frame create --storyboard <S> <TITLE> [opts]` | Add frame; full object. |
| `mesa storyboard frame update <ID> <flags>` | ≥1 field. Storyboard + author immutable. |
| `mesa storyboard frame delete <ID> [--author <A>]` | Delete frame AND edges touching it; echoes `{frame, edges}`. |

create/update flags: `--body <md>` · `--x` `--y` (top-left, canvas units; default 40/40) · `--w` `--h` (default 240/140) · `--color <css>` (e.g. `'#00e5ff'`) · `--task <ID>` (soft link to a task in the same project; cleared if that task is deleted) · `--author <A>`. update adds `--no-task` (unlink). `--body ""` / `--color ""` clear.

Position/size are abstract canvas units the web renders as pixels.

## edge (connections)

| Command | Purpose |
|---|---|
| `mesa storyboard edge create --storyboard <S> --from <F> --to <T> [--label <L>] [--author <A>]` | Directed edge between two frames of the board. |
| `mesa storyboard edge update <ID> --label <L> [--author <A>]` | Relabel only; `--label ""` clears. |
| `mesa storyboard edge delete <ID> [--author <A>]` | Echoes destroyed edge. |

- Both frames must belong to the storyboard.
- Self-edges rejected (code `validation`); cycles allowed.
- Endpoints immutable — to re-route, delete and re-create.

## events — collaboration record

`storyboard events <ID>` → array of `{id, storyboard_id, actor, action, summary, at}`, oldest first. `action` is a stable token: `storyboard_created`, `storyboard_edited`, `frame_added`, `frame_moved`, `frame_edited`, `frame_removed`, `edge_added`, `edge_relabeled`, `edge_removed`. This is the cross-agent/user history.

`--author` on mutating commands is a free-text actor id (agent name or `"user"`) written into that history — set it so the record attributes changes.

## Examples

```bash
SB=$(mesa storyboard create --project 1 "Onboarding flow" --author agent-7 | jq .id)
F1=$(mesa storyboard frame create --storyboard $SB "Land on home" --x 40  --y 40  | jq .id)
F2=$(mesa storyboard frame create --storyboard $SB "Sign up" --task 7 --color '#ff2bd6' --x 320 --y 40 | jq .id)
mesa storyboard edge create --storyboard $SB --from $F1 --to $F2 --label "then" --author agent-7
mesa storyboard frame update $F1 --x 120 --y 80          # move it
mesa storyboard show $SB
```
