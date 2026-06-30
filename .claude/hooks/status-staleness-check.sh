#!/usr/bin/env bash
# Fired by the SessionStart hook (see .claude/settings.json). Its job: if the
# project's STATUS.md hasn't been touched in a while, surface that at the top of the
# session so "In Progress"/Backlog don't silently rot. This is the deterministic
# half of the anti-staleness design — /status also checks, but only if invoked.
#
# STATUS.md is private-by-default and lives at _planning/STATUS.md; fall back to a
# repo-root STATUS.md for projects that chose to make it public there.
set -euo pipefail

STALE_DAYS="${STATUS_STALE_DAYS:-7}"

f="_planning/STATUS.md"
[[ -f "$f" ]] || f="STATUS.md"
[[ -f "$f" ]] || exit 0   # no status file yet (e.g. before /init) — say nothing

# Pull the date out of a "Last updated: YYYY-MM-DD" line.
last="$(grep -m1 -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null | head -1 || true)"
[[ -n "$last" ]] || exit 0  # no parseable date — don't nag

# Age in whole days (GNU date; the dev container has it).
last_s="$(date -d "$last" +%s 2>/dev/null || true)"
[[ -n "$last_s" ]] || exit 0
now_s="$(date +%s)"
days=$(( (now_s - last_s) / 86400 ))

if (( days >= STALE_DAYS )); then
  echo "STATUS_STALE: $f was last updated $last (${days}d ago). Reconcile In Progress/Backlog with reality and run /update-status."
fi
