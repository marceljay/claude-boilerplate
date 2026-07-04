#!/usr/bin/env bash
# Fired by the SessionStart hook (see .claude/settings.json). Its job: surface a
# rotting STATUS.md at the top of the session so "In Progress"/Backlog don't
# silently drift from reality. This is the deterministic half of the
# anti-staleness design — /status also checks, but only if invoked.
#
# Two independent checks:
#   1) STATUS_STALE — the "Last updated" date is older than STATUS_STALE_DAYS
#      (default 7). Catches a file nobody has touched in a while.
#   2) STATUS_DRIFT — "In Progress" has items AND commits have landed since the
#      file was last modified. That's the signature of "work finished but never
#      cleared", and it flags the very next session instead of waiting out the
#      7-day window. (STATUS.md is gitignored, so its mtime only moves on a
#      real local edit — a reliable "last reconciled" signal.)
#
# STATUS.md is private-by-default and lives at _planning/STATUS.md; fall back to a
# repo-root STATUS.md for projects that chose to make it public there.
set -euo pipefail

STALE_DAYS="${STATUS_STALE_DAYS:-7}"

f="_planning/STATUS.md"
[[ -f "$f" ]] || f="STATUS.md"
[[ -f "$f" ]] || exit 0   # no status file yet (e.g. before /init) — say nothing

# --- Check 1: cold file. Pull the date out of a "Last updated: YYYY-MM-DD" line.
last="$(grep -m1 -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null | head -1 || true)"
if [[ -n "$last" ]]; then
  # Age in whole days (GNU date; the dev container has it).
  last_s="$(date -d "$last" +%s 2>/dev/null || true)"
  if [[ -n "$last_s" ]]; then
    now_s="$(date +%s)"
    days=$(( (now_s - last_s) / 86400 ))
    if (( days >= STALE_DAYS )); then
      echo "STATUS_STALE: $f was last updated $last (${days}d ago). Reconcile In Progress/Backlog with reality (update-status skill)."
    fi
  fi
fi

# --- Check 2: drift. In Progress non-empty + commits newer than the file's mtime.
in_progress="$(awk '/^## In Progress/{flag=1; next} /^#|^---/{flag=0} flag' "$f" \
  | grep -cE '^[[:space:]]*-' || true)"
if (( in_progress > 0 )) && git rev-parse --git-dir >/dev/null 2>&1; then
  commit_s="$(git log -1 --format=%ct 2>/dev/null || true)"
  file_s="$(stat -c %Y "$f" 2>/dev/null || true)"
  if [[ -n "$commit_s" && -n "$file_s" ]] && (( commit_s > file_s )); then
    echo "STATUS_DRIFT: commits have landed since $f was last touched, and In Progress lists ${in_progress} item(s). If any are finished, move them to CHANGELOG.md now (update-status skill)."
  fi
fi
