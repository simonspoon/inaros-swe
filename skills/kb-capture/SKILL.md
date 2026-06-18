---
name: kb-capture
description: Save a finding, note, article, or source into the personal knowledge base. Use when the user says "save this to the KB", "remember this in the knowledge base", "ingest this", or wants a lesson/discovery from the current project preserved.
---

# KB Capture

KB = Obsidian vault + git repo at `~/inaros/knowledge/`. Don't improvise its structure.

1. Read `~/inaros/knowledge/CLAUDE.md` — it's the schema: folder layout, naming, frontmatter, areas, **Ingest** workflow.
2. Follow Ingest workflow exactly, every step: raw copy → `wiki/sources/` summary page → concept/entity page updates with cross-links → `index.md` → `log.md` → git commit (run git inside the vault dir).
3. Finding from current project (not external source) → write as dated note in `raw/notes/` first; include enough context (project, problem, what learned) to stand alone, then ingest that note.
4. Confirm to user what was created/updated, as vault-relative paths.
