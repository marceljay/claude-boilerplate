#!/usr/bin/env bash
# Claude Code status line: account rate-limit usage with local reset times.
#
# Reads the status-line JSON on stdin and prints the 5-hour and 7-day usage
# windows plus when each resets, in your local timezone ($TZ), and how full the
# current context window is. Runs locally and
# does NOT consume API tokens — status lines never enter the model context.
#
# `rate_limits` is only present for Claude.ai Pro/Max sessions, and only after
# the first API response of a session; until then this falls back to context %.
# Reset times use GNU `date -d @<epoch>` (Linux / dev container). On a macOS
# host, swap the two `date -d "@$..."` calls for `date -r "$..."`.
#
# TZ is read from the environment. Set it per-machine in your gitignored
# .claude/settings.local.json ("env": { "TZ": "Area/City" }) so this shared
# script shows local time without hardcoding anyone's timezone.
set -euo pipefail

input=$(cat)

vals=$(printf '%s' "$input" | jq -r '
  [ (.rate_limits.five_hour.used_percentage // -1 | floor),
    (.rate_limits.five_hour.resets_at        // 0),
    (.rate_limits.seven_day.used_percentage  // -1 | floor),
    (.rate_limits.seven_day.resets_at        // 0) ] | @tsv')
IFS=$'\t' read -r h_pct h_reset d_pct d_reset <<<"$vals"

# Context-window usage: how full the current conversation is. Shown always —
# it is the number that tells you when to /clear or /compact, and the rate
# limits say nothing about it.
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0 | floor')

# No rate-limit data yet (not Pro/Max, or before the first API response) —
# show only the context usage instead of a blank line.
if [ "$h_pct" -lt 0 ]; then
  printf 'ctx %s%%' "$ctx"
  exit 0
fi

printf '5h %s%% · resets %s   │   7d %s%% · resets %s   │   ctx %s%%' \
  "$h_pct" "$(date -d "@$h_reset" +'%H:%M')" \
  "$d_pct" "$(date -d "@$d_reset" +'%a %H:%M')" "$ctx"
