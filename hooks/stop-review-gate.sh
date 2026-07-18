#!/usr/bin/env bash
# inaros-swe Stop hook — code-review gate.
#
# Blocks finishing a turn that would leave a NON-TRIVIAL, UNCOMMITTED, UNREVIEWED
# diff, instructing the agent to consult the guru reviewer agent (or run
# /code-review) first. Honest scope of what this enforces: it forces (at most) one
# review prompt per distinct diff state — it can't verify the agent actually
# reviewed, only that it was told to before stopping.
#
# Inert when: not a git repo, background work is in flight (see below), diff below
# threshold, a review just ran (see review credit below), or this exact diff was
# already prompted (loop-safe). Committing the change clears the gate (diff vs
# HEAD empties).
#
# Background-work skip (the main agent stopping while work continues isn't a finish):
#   - Orchestration mid-flight — mesa is the pipeline's state of truth; any in_progress
#     task for this repo's cached project (.scratch/mesa.json) means engineers are live.
#   - Skip marker — any background workflow can suppress the gate by touching
#     "$(git rev-parse --git-dir)/inaros-review-gate-off", and re-arm by removing it.
#
# Tunables (env): REVIEW_GATE_MIN_LINES (default 40), REVIEW_GATE_MIN_FILES (default 3).
# To make it ADVISORY instead of blocking: change the final `exit 2` to `exit 0`
# (stderr still surfaces the note, but the agent is not forced to act).

set -uo pipefail

MIN_LINES="${REVIEW_GATE_MIN_LINES:-40}"
MIN_FILES="${REVIEW_GATE_MIN_FILES:-3}"

# Consume stdin payload (tolerate none).
payload="$(cat 2>/dev/null || true)"

root="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$root" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
gitdir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0

# Reviewed state is tracked by diff hash. State lives in .git (never committed).
state="$gitdir/inaros-review-gate"

# Review credit: the PostToolUse hook (review-marker.sh) touches this when a review
# runs. Consume it once and stamp the CURRENT diff as reviewed — the diff produced
# by applying the review's own findings must not re-gate, so credit lands here at
# stop time, not at review time. Consumed BEFORE every skip below, so a marker set
# during a skipped stop can't be banked and spent on a later unrelated diff. Credit
# is timing-based, not content-based (work added after the review rides it) — same
# honest scope as the gate itself.
marker="$gitdir/inaros-review-done"
if [ -e "$marker" ]; then
  rm -f "$marker"
  git diff HEAD | git hash-object --stdin > "$state" 2>/dev/null || rm -f "$state"
  exit 0
fi

# Honor the official stop-loop guard.
case "$payload" in
  *'"stop_hook_active": true'* | *'"stop_hook_active":true'*) exit 0 ;;
esac

# Background work in flight → the stop is the main agent yielding, not finishing. Skip.
# (1) Explicit marker: a background workflow touches this to suppress, removes it to re-arm.
[ -e "$gitdir/inaros-review-gate-off" ] && exit 0
# (2) Orchestration mid-flight: any in_progress mesa task for this repo's cached project.
scratch="$root/.scratch/mesa.json"
if [ -f "$scratch" ] && command -v mesa >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  pid="$(jq -r '.project // empty | if type=="object" then .id else . end' "$scratch" 2>/dev/null)"
  if [ -n "$pid" ]; then
    n="$(mesa task list --project "$pid" --status in_progress 2>/dev/null | jq 'length' 2>/dev/null)"
    [ "${n:-0}" -gt 0 ] && exit 0
  fi
fi

# Tracked changes vs HEAD (staged + unstaged). Binary files ("-") count as 0 lines.
stat="$(git diff HEAD --numstat 2>/dev/null \
  | awk '{a+=($1=="-"?0:$1); d+=($2=="-"?0:$2); f++} END{printf "%d %d", f+0, a+d+0}')"
files="${stat%% *}"; lines="${stat##* }"

# Below both thresholds → nothing worth gating.
if [ "${files:-0}" -lt "$MIN_FILES" ] && [ "${lines:-0}" -lt "$MIN_LINES" ]; then
  exit 0
fi

# Loop guard: prompt at most once per distinct diff.
cur="$(git diff HEAD | git hash-object --stdin 2>/dev/null || echo none)"
prev="$(cat "$state" 2>/dev/null || true)"
[ "$cur" = "$prev" ] && exit 0
printf '%s\n' "$cur" > "$state"

# Block the stop (exit 2). stderr is fed back to the agent.
printf 'Review gate: %s file(s) / %s changed line(s) vs HEAD are uncommitted and not yet reviewed this turn. Consult guru (Agent tool, subagent_type "inaros-swe:guru"; pass ONLY the task/spec pointer, repo path, and diff base ref — never your plan or reasoning) or run /code-review. Address findings, then finish. To skip, state an explicit reason.\n' \
  "$files" "$lines" >&2
exit 2
