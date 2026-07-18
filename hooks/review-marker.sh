#!/usr/bin/env bash
# inaros-swe PostToolUse hook — records that a code review ran this turn.
#
# Fires on ReportFindings (a review reported its findings), Skill(code-review)
# (a review was launched), or Agent(inaros-swe:guru) (a guru consult was launched).
# Touches "$(git rev-parse --git-dir)/inaros-review-done";
# the Stop hook (stop-review-gate.sh) consumes the marker once and treats the diff
# present at that stop — including fixes applied from the review's findings — as
# reviewed. Inert outside a git repo or on unrelated tools.
#
# Known limits (accepted — same honest scope as the Stop gate, which can't verify a
# review actually happened): credit is granted on ANY ReportFindings (sibling flows
# like /security-review or a PR /review also count) and at Skill launch (an aborted
# review still credits). Both triggers are load-bearing: not every review variant
# calls ReportFindings, and a user-typed slash command produces no Skill tool call.

set -uo pipefail

payload="$(cat 2>/dev/null || true)"
case "$payload" in
  *'"tool_name":"ReportFindings"'* | *'"tool_name": "ReportFindings"'*) ;;
  *'"tool_name":"Skill"'* | *'"tool_name": "Skill"'*)
    case "$payload" in
      *'"skill":"code-review"'* | *'"skill": "code-review"'*) ;;
      *) exit 0 ;;
    esac ;;
  *'"tool_name":"Agent"'* | *'"tool_name": "Agent"'*)
    case "$payload" in
      *'"subagent_type":"inaros-swe:guru"'* | *'"subagent_type": "inaros-swe:guru"'*) ;;
      *) exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac

root="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$root" 2>/dev/null || exit 0
gitdir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
touch "$gitdir/inaros-review-done"
exit 0
