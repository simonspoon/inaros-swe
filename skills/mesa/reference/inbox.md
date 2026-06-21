# mesa inbox — global message inbox

One shared, global inbox — NOT per-project. A free-text item lands UNASSIGNED (`project_id: null`); an agent uses it for whatever it wants (update requests, hand-offs, notes to the human). No auto-routing: naming a project in the body does nothing. A person (or `inbox assign`) routes it to a project later.

## Commands

| Command | Purpose |
|---|---|
| `mesa inbox add [--author <A>] <BODY>...` | New unassigned item; full object. Quoting optional — words after `add` are joined. Put `--author` BEFORE the body. |
| `mesa inbox list [--project <P>]` | Items newest first, bare array. No `--project` → the whole inbox (all items); `--project <P>` → only items routed there. |
| `mesa inbox show <ID>` | One item, full object. |
| `mesa inbox assign <PROJECT> <ID>` / `mesa inbox assign --clear <ID>` | Route item to a project, or `--clear` back to unassigned. Exactly one required. Unknown project → validation error. |
| `mesa inbox delete <ID>` | Delete item — no confirmation; echoes destroyed item. |

## Semantics

- **BODY** — the message; everything after `add`, quoting optional (multiple words joined). Agent's call what it means.
- **`--author`** — free-text actor id (agent name or `"user"`); set it so items are attributed across agents/people. Must precede the body or it's swallowed as body text.
- **Unassigned by default** — `add` always lands `project_id: null`. Routing is a deliberate later step (`assign`), done by a human or agent; nothing in the body triggers it.
- **assign** — `<PROJECT|--clear>` then `<ID>`; exactly one of project-id / `--clear`. Assigning to an unknown project → validation error.
- **No update** — items have no edit command; fix a wrong message by `delete` + `add`, or re-route with `assign`.
- **delete** — no prompt; echoes destroyed item (recoverable transcript).
- **Object shape** — `{id, project_id, author, body, created_at, updated_at}`. Unassigned → `project_id: null`; after `assign` → the project id.

## Examples

```bash
mesa inbox add --author agent-7 "the auth refactor is ready for review"
mesa inbox list                       # whole inbox, newest first
mesa inbox assign 1 3                 # route item 3 to project 1
mesa inbox assign --clear 3           # send it back to unassigned
mesa inbox list --project 1           # only items routed to project 1
```
