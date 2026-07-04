#!/usr/bin/env bash
# Fired by the PreCompact hook (see .claude/settings.json) just before the
# conversation is auto-summarized. Its job: leave a durable, deterministic trace
# so session state is never silently lost to compaction.
#
# This runs regardless of whether Claude "remembers" to save — that's the whole
# point of a hook. See .claude/README.md section 2 for how hooks work.
set -euo pipefail

ts="$(date '+%Y-%m-%d %H:%M')"
# STATUS.md is private-by-default at _planning/STATUS.md; fall back to repo root.
status_file="_planning/STATUS.md"
[[ -f "$status_file" ]] || status_file="STATUS.md"

# Leave a timestamped compaction marker. The marker is a breadcrumb, not a log:
# any previous marker is replaced, so repeated compactions don't pile up cruft
# in STATUS.md (the update-status skill also deletes stale ones when editing).
if [[ -f "$status_file" ]]; then
  content="$(sed '/^<!-- context compacted at /d' "$status_file")"
  printf '%s\n\n<!-- context compacted at %s — review In Progress/Blockers above -->\n' \
    "$content" "$ts" > "$status_file"
fi

# Emit the cue Claude is told to watch for, so it also does the richer,
# judgment-based save (updating In Progress, plans, memory).
echo "CONTEXT_SAVE_TRIGGERED at $ts"
