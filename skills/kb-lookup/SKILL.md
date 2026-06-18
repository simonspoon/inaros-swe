---
name: kb-lookup
description: Look up what the personal knowledge base knows about a topic. Use when the user asks to "check the KB" / "what do we know about X", or when a task touches software development or AI harness/skill/tooling topics where curated prior knowledge would help. Read-only.
---

# KB Lookup

KB = Obsidian vault at `~/inaros/knowledge/`. Read-only for this skill — don't create, edit, or move anything (use kb-capture for writes).

1. Read `~/inaros/knowledge/index.md` — every wiki page listed, one-line summary, grouped by area.
2. Read relevant pages under `wiki/` (sources, concepts, entities, syntheses). Follow `[[wikilinks]]` to related pages when load-bearing; `[[Page Name]]` resolves to `wiki/*/Page Name.md`.
3. Wiki pages thin → cited raw source under `raw/` has full detail; frontmatter `sources:` lists them.
4. Answer grounded in what you read, cite pages by name (e.g. "per the KB's *Tool Use* concept page"). KB has nothing relevant → say so plainly. Don't pad with general knowledge presented as KB content.
