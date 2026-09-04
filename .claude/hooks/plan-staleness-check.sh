#!/usr/bin/env bash
# Fired by the SessionStart hook (see .claude/settings.json). The sibling of
# status-staleness-check.sh, for the other half of the working state: the
# plans in _planning/plans/.
#
# The failure it catches: a plan is written, work proceeds against it, commits
# land — and the plan's checkboxes stop matching them, because updating the
# plan is the step that feels optional once the code is green. By the time
# anyone reads it back it says the work is unstarted, gets believed, and the
# real state has to be rebuilt from `git log` — exactly what the plan existed
# to save. (A downstream repo retired a plan with 28 open boxes, 25 of them
# describing shipped work.) CLAUDE.md's rule is the fix — a plan is not a
# queue, open items live in STATUS.md — and this hook is the backstop for a
# plan that accumulates boxes anyway.
#
# Only *open* plans are checked. A plan whose boxes are all ticked is a record,
# not a queue, and cannot rot. Unlike STATUS.md (gitignored, so its mtime is a
# reliable "last reconciled" signal), plans are usually tracked, so "last
# touched" is `git log -1 -- <file>`: survives checkouts and clones.
set -euo pipefail

DIR="_planning/plans"
# Commits that may land against an open plan before it counts as stale. Two is
# noise (a fix and its follow-up); three is a session's worth of work the plan
# has not heard about.
THRESHOLD="${PLAN_STALE_COMMITS:-3}"

[[ -d "$DIR" ]] || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

shopt -s nullglob
for f in "$DIR"/*.md; do
  # Open items only: `- [ ]` not started, `- [~]` in progress.
  open="$(grep -cE '^[[:space:]]*- \[( |~)\]' "$f" || true)"
  (( open > 0 )) || continue

  # Edited but not yet committed — this session is already on it; say nothing.
  git diff --quiet HEAD -- "$f" 2>/dev/null || continue

  last="$(git log -1 --format=%H -- "$f" 2>/dev/null || true)"
  # Never committed: it is new, and new is not stale.
  [[ -n "$last" ]] || continue

  since="$(git rev-list --count "$last..HEAD" 2>/dev/null || echo 0)"
  if (( since >= THRESHOLD )); then
    echo "PLAN_DRIFT: ${f#"$DIR"/} has ${open} open item(s) and ${since} commit(s) have landed since it was last updated. Check each open box against the tree; move what is still outstanding to STATUS.md and retire the plan if it has gone quiet (/plans, update-status skill)."
  fi
done
