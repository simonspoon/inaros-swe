# Contributing

Thanks for your interest. A few things up front so we don't waste each other's time.

This is a **personal, opinionated** plugin. It encodes one developer's workflow and taste (see [`CLAUDE.md`](CLAUDE.md)). Bug fixes, portability improvements, and docs are very welcome. Larger behavioral changes may be declined if they pull against that workflow — please **open an issue to discuss before writing a big PR**.

## Ground rules (they mirror `CLAUDE.md`)

- **Keep it simple.** Smallest change that solves the stated problem. No speculative abstraction, options, or "while I'm here" refactors.
- **Surgical diffs.** Touch only what the change requires. Match the existing style even if you'd write it differently.
- **Understand before changing.** Don't edit a skill or agent you can't explain.

## Working on skills & agents

- **Skills** live in `skills/<name>/SKILL.md`; **agents** in `agents/<name>.md`. Both use YAML frontmatter (`name`, `description`) followed by the instruction body.
- **Register:** skill/agent **instruction bodies** are written in a *telegraphic* register — dropped function words, imperative clauses, high information density. Match it when editing a body. **Exceptions stay natural prose:** frontmatter `description:` (the harness matches on it for invocation), user-facing output the skill emits, and any code/commands/templates (kept verbatim).
- **Descriptions matter.** The `description:` field is how Claude decides when to invoke a skill/agent — make it precise about *when to use* and *when not to*.

## Testing a change

There's no compiler here — most of this is Markdown instructions. Verify the way the change allows:

- **Behavioral changes to a skill/agent:** use the bundled [`improve-skill`](skills/improve-skill) skill — it drafts test cases from the target's stated job, runs it via subagents, scores outputs with an LLM judge, and re-tests. That's the strongest available check.
- **Hook changes:** the hooks are plain bash — run them directly with a sample payload on stdin. For `hooks/stop-review-gate.sh`, confirm the exit code (`0` = allow, `2` = block). For `hooks/review-marker.sh` (always exits `0`), confirm the side effect: `.git/inaros-review-done` is touched for a ReportFindings or Skill(code-review) payload and untouched otherwise.
- **JSON manifests** (`plugin.json`, `marketplace.json`): validate they parse (`jq . <file>`).

## Submitting

1. Fork, branch from `main`.
2. Make the change; keep the diff focused.
3. Describe **what** changed and **why** in the PR. Link the issue if there is one.

By contributing you agree your work is licensed under the repo's [MIT License](LICENSE).
