# mesa serve

Start the HTTP server + web UI (renders storyboards, browse projects/tasks). Long-running — run in background, not a one-shot.

```
mesa serve [--port <PORT>]      # default 7770
```

- Binds **127.0.0.1 only** — local, not network-exposed.
- Requests must carry `Host: localhost:<port>` or `127.0.0.1:<port>`.
- Mutating requests must set `Content-Type: application/json`.
- Serves the same DB the CLI uses (`MESA_DB` honored).

```bash
mesa serve --port 7770          # then open http://localhost:7770
```

Starting/stopping the server is an environment action — launch it in the background and report the URL; don't block the session waiting on it.
