# mesa project

Top container. Owns tasks + storyboards; deleting one cascades to all of them.

## Commands

| Command | Purpose |
|---|---|
| `mesa project create <NAME> [--description <D>]` | Create; prints full created project. |
| `mesa project list` | All projects, bare JSON array. |
| `mesa project show <ID>` | One project, full object. |
| `mesa project update <ID> <--name <N> \| --description <D>>` | Change passed fields only; ≥1 required. |
| `mesa project delete <ID>` | Delete project AND all its tasks — no confirmation, cascades immediately. |

## Semantics

- **update** — pass only what changes; at least one flag required. `--description ""` clears the description.
- **delete** — cascades to every task in the project instantly. Output echoes the deleted project plus every cascaded task in full (recoverable transcript). Want a net → `mesa backup <path>` first.

## Examples

```bash
mesa project create "Website redesign" --description "Q3 marketing site"
PID=$(mesa project create "API v2" | jq .id)   # capture id for downstream task creates
mesa project update 1 --description ""          # clear description
mesa project show 1
```
