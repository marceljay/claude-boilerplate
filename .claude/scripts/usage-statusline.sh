#!/usr/bin/env bash
# Claude Code status line: rate-limit usage, context fill, git position, dev server.
#
# Reads the status-line JSON on stdin and prints:
#   5h 12% · resets 17:46 │ 7d 41% · resets Wed 12:26 │ ctx 37% │ main@e416bcc │ dev up :3000
#
# - 5h / 7d: account rate-limit windows with their reset times in local time
#   ($TZ). Only present for Claude.ai Pro/Max sessions, and only after the
#   first API response; before that those two segments are omitted.
# - ctx: how full the current context window is — the number that says when
#   to /clear or /compact.
# - git: current branch and short sha of the checked-out commit. In a linked
#   worktree (`git worktree add`, `claude --worktree`) the worktree's directory
#   name follows: `feat-x@3f2a1c0 wt:feat-x`. Detached HEAD shows `@sha` only.
#   Omitted outside a git repository.
# - dev: whether a dev server is listening. Checks the port recorded as
#   `Dev port: <port>` in .claude/CUSTOM.md (or CLAUDE.md) first, then the
#   usual dev ports (3000 5173 8000 5000 4321 8080). Prints `dev up :<port>`
#   or `dev down`.
#
# Runs locally on every response and does NOT consume API tokens — status
# lines never enter the model context. Needs `jq`; git and the port probe
# (`ss`, else `netstat`/`lsof`) degrade to their segment being omitted.
# Reset times use GNU `date -d @<epoch>` (Linux / dev container). On a macOS
# host, swap the two `date -d "@$..."` calls for `date -r "$..."`.
#
# TZ is read from the environment. Set it per-machine in your gitignored
# .claude/settings.local.json ("env": { "TZ": "Area/City" }) so this shared
# script shows local time without hardcoding anyone's timezone.
set -uo pipefail

input=$(cat)
sep='   │   '
segments=()

vals=$(printf '%s' "$input" | jq -r '
  [ (.rate_limits.five_hour.used_percentage // -1 | floor),
    (.rate_limits.five_hour.resets_at        // 0),
    (.rate_limits.seven_day.used_percentage  // -1 | floor),
    (.rate_limits.seven_day.resets_at        // 0),
    (.context_window.used_percentage         // 0  | floor),
    (.workspace.current_dir // .cwd // "") ] | @tsv' 2>/dev/null) \
  || { printf 'ctx ?'; exit 0; }   # no jq, or odd input: say so rather than go blank
IFS=$'\t' read -r h_pct h_reset d_pct d_reset ctx dir <<<"$vals"
[ -n "$dir" ] || dir=$PWD

# --- rate limits (Pro/Max only, after the first response) -------------------
if [ "$h_pct" -ge 0 ]; then
  segments+=("5h ${h_pct}% · resets $(date -d "@$h_reset" +'%H:%M')")
  segments+=("7d ${d_pct}% · resets $(date -d "@$d_reset" +'%a %H:%M')")
fi

# --- context window ---------------------------------------------------------
segments+=("ctx ${ctx}%")

# --- git: branch@sha, plus worktree name when in a linked worktree -----------
if sha=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null); then
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
  common_dir=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
  [ "$branch" = "HEAD" ] && branch=''          # detached HEAD
  seg="${branch}@${sha}"
  # A linked worktree has its own .git dir under <main>/.git/worktrees/<name>.
  if [ "$git_dir" != "$common_dir" ] && [[ "$git_dir" == */worktrees/* ]]; then
    seg+=" wt:$(basename "$top")"
  fi
  segments+=("$seg")
fi

# --- dev server: recorded port first, then common dev ports ------------------
listening=$(ss -tlnH 2>/dev/null | awk '{print $4}' \
  || netstat -an 2>/dev/null | awk '/LISTEN/{print $4}' \
  || lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}')
listening=$(printf '%s\n' "$listening" | sed -E 's/.*[:.]([0-9]+)$/\1/' | sort -un)

candidates=()
for f in "$dir/.claude/CUSTOM.md" "$dir/CLAUDE.md" "$dir/.claude/CLAUDE.md"; do
  [ -f "$f" ] || continue
  p=$(grep -oE '^[-* ]*Dev port:[[:space:]]*[0-9]+' "$f" 2>/dev/null | grep -oE '[0-9]+$' | head -1)
  [ -n "$p" ] && { candidates+=("$p"); break; }
done
candidates+=(3000 5173 8000 5000 4321 8080)

dev='dev down'
for p in "${candidates[@]}"; do
  if printf '%s\n' "$listening" | grep -qx "$p"; then dev="dev up :$p"; break; fi
done
segments+=("$dev")

# --- print ------------------------------------------------------------------
out=''
for s in "${segments[@]}"; do out+="${out:+$sep}$s"; done
printf '%s' "$out"
