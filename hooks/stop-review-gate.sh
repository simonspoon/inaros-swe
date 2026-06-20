#!/usr/bin/env bash
# inaros-swe Stop hook — code-review gate.
#
# Blocks finishing a turn that would leave a NON-TRIVIAL, UNCOMMITTED, UNREVIEWED
# diff, instructing the agent to run /code-review first. Honest scope of what this
# enforces: it forces (at most) one review prompt per distinct diff state — it can't
# verify the agent actually reviewed, only that it was told to before stopping.
#
# Inert when: not a git repo, diff below threshold, or this exact diff was already
# prompted (loop-safe). Committing the change clears the gate (diff vs HEAD empties).
#
# Tunables (env): REVIEW_GATE_MIN_LINES (default 40), REVIEW_GATE_MIN_FILES (default 3).
# To make it ADVISORY instead of blocking: change the final `exit 2` to `exit 0`
# (stderr still surfaces the note, but the agent is not forced to act).

set -uo pipefail

MIN_LINES="${REVIEW_GATE_MIN_LINES:-40}"
MIN_FILES="${REVIEW_GATE_MIN_FILES:-3}"

# Consume stdin payload (tolerate none). Honor the official stop-loop guard.
payload="$(cat 2>/dev/null || true)"
case "$payload" in
  *'"stop_hook_active": true'* | *'"stop_hook_active":true'*) exit 0 ;;
esac

root="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$root" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Tracked changes vs HEAD (staged + unstaged). Binary files ("-") count as 0 lines.
stat="$(git diff HEAD --numstat 2>/dev/null \
  | awk '{a+=($1=="-"?0:$1); d+=($2=="-"?0:$2); f++} END{printf "%d %d", f+0, a+d+0}')"
files="${stat%% *}"; lines="${stat##* }"

# Below both thresholds → nothing worth gating.
if [ "${files:-0}" -lt "$MIN_FILES" ] && [ "${lines:-0}" -lt "$MIN_LINES" ]; then
  exit 0
fi

# Loop guard: prompt at most once per distinct diff. State lives in .git (never committed).
gitdir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
state="$gitdir/inaros-review-gate"
cur="$(git diff HEAD | git hash-object --stdin 2>/dev/null || echo none)"
prev="$(cat "$state" 2>/dev/null || true)"
[ "$cur" = "$prev" ] && exit 0
printf '%s\n' "$cur" > "$state"

# Block the stop (exit 2). stderr is fed back to the agent.
printf 'Code-review gate: %s file(s) / %s changed line(s) vs HEAD are uncommitted and not yet reviewed this turn. Run /code-review on the current diff, address its findings, then finish. To skip, state an explicit reason.\n' \
  "$files" "$lines" >&2
exit 2
