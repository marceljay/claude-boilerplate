#!/usr/bin/env bash
# Claude Code status line: rate-limit usage, context fill, git position, dev server.
#
# Reads the status-line JSON on stdin and prints:
#   5h 12% · resets 17:46 │ 7d 41% · resets Wed 12:26 │ ctx 37% │ main@e416bcc │ dev server up :3000
#
# - 5h / 7d: account rate-limit windows with their reset times in local time
#   ($TZ). Only present for Claude.ai Pro/Max sessions, and only after the
#   first API response; before that those two segments are omitted.
# - ctx: how full the current context window is — the number that says when
#   to /clear or /compact.
# - git: current branch and short sha of the checked-out commit, then commits
#   ahead/behind the upstream as of the last fetch (`↑2 ↓1`, only when
#   non-zero; nothing without an upstream). In a linked
#   worktree (`git worktree add`, `claude --worktree`) the worktree's directory
#   name follows: `feat-x@3f2a1c0 wt:feat-x`. Detached HEAD shows `@sha` only.
#   Omitted outside a git repository.
# - dev server: whether one is listening, shown only for projects that have
#   one (a recorded `Dev port:`, a package.json dev/start/serve script, a
#   Django manage.py, a Makefile dev/run/serve target, or a Vite/Next/Astro/
#   Nuxt/SvelteKit config). Checks the recorded port first, then the usual
#   dev ports (3000 5173 8000 5000 4321 8080). Prints `dev server up :<port>`
#   (suffixed `(container)` inside the dev container, where the host-side
#   forwarded port can differ) or `dev server down`; omitted for projects
#   without a dev server.
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
  # Ahead/behind the upstream as of the last fetch (no network here). Shown
  # only when non-zero; nothing when the branch has no upstream.
  if ab=$(git -C "$dir" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null); then
    read -r ahead behind <<<"$ab"
    [ "$ahead"  -gt 0 ] && seg+=" ↑$ahead"
    [ "$behind" -gt 0 ] && seg+=" ↓$behind"
  fi
  # A linked worktree has its own .git dir under <main>/.git/worktrees/<name>.
  if [ "$git_dir" != "$common_dir" ] && [[ "$git_dir" == */worktrees/* ]]; then
    seg+=" wt:$(basename "$top")"
  fi
  segments+=("$seg")
fi

# --- dev server: only for projects that have one --------------------------
# The segment appears when a `Dev port:` is recorded in .claude/CUSTOM.md (or
# CLAUDE.md), or the project shows a dev-server signal: a package.json with a
# dev/start/serve script, a Django manage.py, a Makefile dev/run/serve target,
# or a Vite/Next/Astro/Nuxt/SvelteKit config. Libraries, CLIs, and plain
# repos get no segment at all.
recorded=''
for f in "$dir/.claude/CUSTOM.md" "$dir/CLAUDE.md" "$dir/.claude/CLAUDE.md"; do
  [ -f "$f" ] || continue
  recorded=$(grep -oE '^[-* ]*Dev port:[[:space:]]*[0-9]+' "$f" 2>/dev/null | grep -oE '[0-9]+$' | head -1)
  [ -n "$recorded" ] && break
done

has_dev_server=false
[ -n "$recorded" ] && has_dev_server=true
[ -f "$dir/package.json" ] \
  && jq -e '.scripts | has("dev") or has("start") or has("serve")' "$dir/package.json" >/dev/null 2>&1 \
  && has_dev_server=true
[ -f "$dir/manage.py" ] && has_dev_server=true
[ -f "$dir/Makefile" ] && grep -qE '^(dev|run|serve):' "$dir/Makefile" 2>/dev/null && has_dev_server=true
for c in vite.config next.config astro.config nuxt.config svelte.config; do
  compgen -G "$dir/$c.*" >/dev/null 2>&1 && { has_dev_server=true; break; }
done

if $has_dev_server; then
  listening=$(ss -tlnH 2>/dev/null | awk '{print $4}' \
    || netstat -an 2>/dev/null | awk '/LISTEN/{print $4}' \
    || lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}')
  listening=$(printf '%s\n' "$listening" | sed -E 's/.*[:.]([0-9]+)$/\1/' | sort -un)

  candidates=(${recorded:+"$recorded"} 3000 5173 8000 5000 4321 8080)
  # Inside the dev container the host-side forwarded port can differ and is
  # not readable here, so label the port as the container's.
  where=''
  [ -n "${REMOTE_CONTAINERS:-}${DEVCONTAINER:-}" ] && where=' (container)'
  dev='dev server down'
  for p in "${candidates[@]}"; do
    if printf '%s\n' "$listening" | grep -qx "$p"; then dev="dev server up :$p$where"; break; fi
  done
  segments+=("$dev")
fi

# --- print ------------------------------------------------------------------
out=''
for s in "${segments[@]}"; do out+="${out:+$sep}$s"; done
printf '%s' "$out"
