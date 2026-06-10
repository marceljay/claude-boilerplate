#!/usr/bin/env bash
# Fired by the PreCompact hook (see .claude/settings.json) just before the
# conversation is auto-summarized. Its job: leave a durable, deterministic trace
# so session state is never silently lost to compaction.
#
# This runs regardless of whether Claude "remembers" to save — that's the whole
# point of a hook. See .claude/README.md section 2 for how hooks work.
set -euo pipefail

ts="$(date '+%Y-%m-%d %H:%M')"
status_file="STATUS.md"

# Append a compaction marker so there's always a timestamped breadcrumb.
if [[ -f "$status_file" ]]; then
  {
    printf '\n<!-- context compacted at %s — review In Progress/Blockers above -->\n' "$ts"
  } >> "$status_file"
fi

# Emit the cue Claude is told to watch for, so it also does the richer,
# judgment-based save (updating In Progress, plans, memory).
echo "CONTEXT_SAVE_TRIGGERED at $ts"
