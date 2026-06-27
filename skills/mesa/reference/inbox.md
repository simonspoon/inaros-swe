# mesa inbox — global message inbox

One shared, global inbox — NOT per-project. A free-text item lands UNASSIGNED (`project_id: null`); an agent uses it for whatever it wants (update requests, hand-offs, notes to the human). No auto-routing: naming a project in the body does nothing. A person routes it later with `inbox assign`, which **converts** it into a todo task in that project.

## Commands

| Command | Purpose |
|---|---|
| `mesa inbox add [--author <A>] <BODY>...` | New unassigned item; full object. Quoting optional — words after `add` are joined. Put `--author` BEFORE the body. |
| `mesa inbox list [--project <P>]` | Items newest first, bare array. Items are never assigned (assign converts + deletes), so `--project` is vestigial — only the no-filter whole-inbox listing is meaningful. |
| `mesa inbox show <ID>` | One item, full object. |
| `mesa inbox assign <ID> <PROJECT>` | Convert item into a todo task in PROJECT and delete it from the inbox. Both args required. **Prints the created task** (not the item). Unknown project → validation error (item left untouched). |
| `mesa inbox delete <ID>` | Delete item — no confirmation; echoes destroyed item. |

## Semantics

- **BODY** — the message; everything after `add`, quoting optional (multiple words joined). Agent's call what it means.
- **`--author`** — free-text actor id (agent name or `"user"`); set it so items are attributed across agents/people. Must precede the body or it's swallowed as body text.
- **Unassigned for life** — `add` lands `project_id: null` and it stays that way until assigned; there is no "assigned but still in the inbox" state, because `assign` converts the item and removes it.
- **assign = convert** — `<ID>` then `<PROJECT>` (both required; no `--clear`). Creates a todo task in PROJECT (title = body's first non-empty line, truncated to 120 chars; full body as the task description; priority medium) and deletes the item — atomic. Prints the created **task**. Item's `author` is not carried onto the task. Unknown project → validation error, item untouched.
- **No update** — items have no edit command; fix a wrong message by `delete` + `add`. There is no re-route (assign is one-way: it converts).
- **delete** — no prompt; echoes destroyed item (recoverable transcript).
- **Object shape** — `{id, project_id, author, body, created_at, updated_at}`, `project_id` always `null` while the item exists. `assign` returns the created **task** object instead.

## Examples

```bash
mesa inbox add --author agent-7 "the auth refactor is ready for review"
mesa inbox list                       # whole inbox, newest first
mesa inbox assign 3 1                 # convert item 3 into a todo task in project 1
mesa inbox delete 3                   # drop item 3 without converting
```
