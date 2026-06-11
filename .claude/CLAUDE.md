# Global Claude Code Instructions

These load on every message — keep them lean. How the harness works (hooks,
agents, commands, state files) is documented in `.claude/README.md`.

## Communication Style
- Be concise. Skip preamble; don't narrate what you're about to do. Show results
  and summarize what changed.

## Token Optimization
- Read files with targeted line ranges (`offset`/`limit`), not whole files.
- Delegate broad codebase reading to the `explore` subagent and diff reviews to
  the `review` subagent — keeps the main context small.
- Don't re-read files right after editing them. Summarize output; don't dump it.

## Safety Net (bypassPermissions mode is ON)
All actions are auto-approved, so:
- Announce destructive actions (`rm`, `git reset`, drop table, etc.) before running.
- Commit atomically — small, focused commits that `git revert` cleanly.
- Never force-push to main/master without explicit confirmation.
- Never delete files outside the project dir without confirmation.
- Never modify `~/.claude/settings.json` or `~/.claude/CLAUDE.md` without showing
  the change and getting a yes.

## Git Conventions
- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`),
  under 72 chars. Branches: `feat/…`, `fix/…`, `chore/…`.
- **Commit policy is a per-project choice.** If none is recorded, ask at the
  first natural commit point (use the Preference Persistence options below):
  1. **On request only** — commit only when the user says so (default until set)
  2. **At milestones** — commit automatically after each completed, verified
     unit of work
  3. **Periodically** — commit at natural pauses / end of session
  Record the choice in the project CLAUDE.md as a one-liner
  (`Commit policy: on-request | milestones | periodic`). Until it's set,
  don't commit unasked.
- Commit policy: milestones (this repo).

## Code Quality
- After editing code, run the project's linter and fix errors without asking.
  Run existing tests; don't write new ones unless asked.
- Treat build/lint/compiler warnings as errors — investigate and fix every one.
  Never say a warning is "safe to ignore"; if one truly can't be fixed, explain
  specifically and ask the user to confirm it's acceptable.
- Co-locate related files (component, hook, types) over splitting by type.

## Error Recovery
- On failure, try one fix. If the second attempt fails, stop and explain what was
  tried, what's unknown, and what input would help (logs, console, screenshots).
  Do NOT loop on the same failing approach.

## Security
- Never commit secrets. Before any commit, confirm `.env*`, `*.pem`, `*.key`,
  `credentials.json`, etc. are gitignored; if not, add them and warn the user.
  (`/init` sets up `.gitignore`/`.gitattributes` for new projects.)
- Flag hardcoded keys/tokens/passwords/connection strings and move them to env vars.
- Never write secrets to any CLAUDE.md or memory file.

## Preference Persistence
When offering a session-scoped Yes/No, add a third option to save globally, and
recommend it (session-only prefs are lost on `/clear` and compaction):
```
1. Yes   2. Yes, always (session)   3. Yes, always (save globally)
```
On option 3: behavioral prefs → append to `~/.claude/CLAUDE.md`; tool permissions
→ add to `~/.claude/settings.json` under `permissions.allow`.

## Project State
CLAUDE.md is for stable instructions only — no TODOs, changelogs, or status here.
State files own one tense each, and an item moves between them (never copied):
`STATUS.md` = now (≤3 in-progress items + blockers), `_planning/backlog.md` =
future (the only queue, priority-ordered), `CHANGELOG.md` = past (the only
completion record). `/init` scaffolds these; see `.claude/README.md` §6.
Read STATUS.md and skim `_planning/backlog.md` alongside CLAUDE.md at session
start. Manage via `/status`, `/update-status`, `/log`, `/backlog`, `/plans`.
On exiting Plan Mode, save the plan to `_planning/plans/YYYY-MM-DD-name.md`
with checkboxed steps.
A cold memory snapshot lives at `_planning/memory-backup/` (`/backup-memory`
refreshes it). Don't read it in normal work — only when memory seems missing or
you need detail the live index lacks; `/backup-memory restore` after a volume wipe.

## Context Save on Compaction
The `PreCompact` hook leaves a marker in STATUS.md automatically. When you also
see `CONTEXT_SAVE_TRIGGERED` (or the chat is very long), proactively update
STATUS.md (in-progress, blockers), any active plan, memory, and CHANGELOG.md,
then tell the user it's safe to `/clear`.
