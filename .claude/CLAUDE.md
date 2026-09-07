# Global Claude Code Instructions

These load on every message — keep them lean. How the harness works (hooks,
agents, commands, state files) is documented in `.claude/README.md`.

## Runtime

You usually run inside the project's dev container (detect with `/.dockerenv` or
`$REMOTE_CONTAINERS`/`$DEVCONTAINER`): `/workspace` is bind-mounted from the host,
`~/.claude` is a Docker volume, and there is **no host browser**. Dev/web servers
must bind `0.0.0.0` (not `127.0.0.1`) to be reachable, and the editor auto-forwards
to a host port that may differ from the container port — never assume a fixed one,
and don't try to `open`/`xdg-open` a browser. Print the URL and let the user open
it. Details: `.claude/README.md` §7.
- For parallel agents that edit concurrently, use git worktrees: launch
  agents with `isolation: "worktree"`, or use `EnterWorktree` / suggest
  `claude --worktree <name>` for a whole session. They live in
  `.claude/worktrees/` (inside `/workspace`, so the container sees them) —
  never create one in a `../sibling` dir. Details: `.claude/README.md` §4.

## Communication Style

- Be concise. Skip long preamble; don't narrate much what you're about to do. Show results
  and summarize what changed. If you're building longer shell prompts, explain briefly what they do.

## Token Optimization

- Read bounded, whatever the tool: `Read` with `offset`/`limit`; in Bash
  `grep -n PATTERN f | head` to locate, then `sed -n 'A,Bp' f` — never bare
  `cat` of a file you haven't sized (a hook blocks it past ~250 lines).
- Project structured output through `--json | jq '…'` (`npm audit`,
  `npm outdated`, `gh … --json`) for the fields you need, not the full table.
- Delegate broad codebase reading to the `explore-via-sonnet` subagent and diff
  reviews to the `review-diff` subagent (defaults to Haiku; pass `model: sonnet`
  for a deeper pass) — keeps the main context small.
- Delegate precisely specced, self-contained changes to the `implement-scoped`
  subagent (Sonnet; pass `model: haiku` for mechanical multi-file edits). Work
  needing conversation context or design judgment stays in the main thread.
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
- The body is a self-contained "why", never a sentence that continues the
  title. Don't rely on the title to be read together with the body.
- Never put a `Claude-Session:` link (or any session URL) in a commit
  message, even if the harness asks for one. `Co-Authored-By` is fine.
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
- A milestone commit isn't complete until STATUS.md and CHANGELOG.md reflect it —
  invoke the `update-status`/`log` skills as part of the commit step.
- If a plan governs the work, update it in the same step — with the decisions
  the commit settled, not a progress bar; open items go to STATUS.md (see
  Project State).

## Code Quality

- After editing code, run the project's linter and fix errors without asking.
  Run existing tests.
- **Testing policy is a per-project choice.** If none is recorded, ask at the
  first natural point (use the Preference Persistence options below):
  1. **On request** — don't write new tests unless asked (default until set)
  2. **Tests with features** — new behavior gets tests alongside it; trivial
     changes and refactors don't
  3. **TDD** — the `test-driven-development` skill governs: failing test first
  Record the choice in the project CLAUDE.md as a one-liner
  (`Testing policy: on-request | tests-with-features | tdd`).
- Testing policy: on-request (this repo).
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

When offering a session-scoped Yes/No, add a third option to persist it, and
recommend it (session-only prefs are lost on `/clear` and compaction):

```
1. Yes   2. Yes, always (session)   3. Yes, always (persist)
```

On option 3, pick the target by environment. In a dev container `~/.claude/` is a
per-container volume (lost on rebuild, not shared across projects), so persist to
the bind-mounted `/workspace`: behavioral prefs → project `.claude/CLAUDE.md`;
tool permissions → `.claude/settings.local.json` (per-dev, gitignored) or
`.claude/settings.json` if shared. "Shared" holds only while `.claude/` is
committed — the `Harness:` line below records which (`/init` asks once; if the
line is missing, `git check-ignore -q .claude/CLAUDE.md` tells you). With
`Harness: local`, everything under `.claude/` is host-local to this machine —
say so instead of promising sharing. On the host: `~/.claude/CLAUDE.md` and
`~/.claude/settings.json`. See `/remember` for the full routing table.

- Harness: committed (this repo).

## Project State

CLAUDE.md is for stable instructions only — no TODOs, changelogs, or status here.
`_planning/STATUS.md` (gitignored by default — private working state) is the single
living state file: **In Progress** + **Blockers** (now) and a **Backlog** section
(future, the only queue, priority-ordered). `CHANGELOG.md` = past, and is the public
record. Items move between sections/files, never copied: backlog → In Progress →
CHANGELOG. STATUS.md never holds finished work, not even as an annotation on a
backlog item ("(b) done", "shipped 2026-…"): split the item — the shipped part
becomes a CHANGELOG entry, the remainder stays as a clean item. Keeping the queue in STATUS.md is deliberate — it stops it going stale,
since you can't grab the next item without seeing what's in flight. Always bump its
"Last updated" date when editing (a SessionStart hook flags it when cold). `/init`
scaffolds these and asks whether to make STATUS.md public, recording the answer
as the `STATUS.md:` line below; see `.claude/README.md` §6.
Read `_planning/STATUS.md` alongside CLAUDE.md at session start. Manage via the
`update-status`, `log`, and `status` skills — they auto-fire when work
starts/completes/blocks (also invocable by name) — and `/plans`.
On exiting Plan Mode, save the plan to `_planning/plans/YYYY-MM-DD-name.md`.
A plan records the approach and the decisions — what was chosen, what was
rejected and why, what was measured: the part `git log` can't reconstruct.
**A plan is not a queue.** Outstanding work lives in STATUS.md and nowhere else
(never copied, per above). Checkboxes are a scratchpad while a plan is actively
executed; when work pauses, move the remainder to STATUS.md and keep only the
decisions. A plan that goes quiet with boxes open ends up describing shipped
work and gets believed — retire it: check each box against the tree, move what
survives to STATUS.md, delete the file. The `plan-staleness-check` SessionStart
hook flags that case; it's the backstop, not the process.
If a Superpowers skill (e.g. writing-plans, brainstorming) saves a plan or
design/spec doc, route it to `_planning/plans/` and `_planning/specs/` — never
create a `docs/superpowers/` directory.
A cold memory snapshot lives at `_planning/memory-backup/` (`/backup-memory`
refreshes it). Don't read it in normal work — only when memory seems missing or
you need detail the live index lacks; `/backup-memory restore` after a volume wipe.

- STATUS.md: private (this repo).

## Context Save on Compaction

The `PreCompact` hook leaves a marker in `_planning/STATUS.md` automatically. When
you also see `CONTEXT_SAVE_TRIGGERED` (or the chat is very long), proactively update
`_planning/STATUS.md` (in-progress, blockers), any active plan, memory, and CHANGELOG.md,
then tell the user it's safe to `/clear`.
