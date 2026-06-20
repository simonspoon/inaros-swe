# mesa backup

Snapshot the database to a file — safe to run while the server is live.

```
mesa backup <PATH>
```

- Uses SQLite `VACUUM INTO` — safe under WAL mode (unlike copying the .db file directly).
- Destination **must not already exist** — fails otherwise.
- Take one before any `delete` you want recoverable (deletes cascade with no confirmation).

## Restore / read a snapshot

Point `MESA_DB` at the snapshot — no import step:

```bash
mesa backup /tmp/mesa-snap.db              # create
MESA_DB=/tmp/mesa-snap.db mesa task list   # read it without touching the live DB
```

To restore as the working DB, point `MESA_DB` at the snapshot (or copy it to the default path while the server is stopped).
