# Global Claude Code Instructions

These load on every message — keep them lean: rules here, rationale in
`.claude/README.md`. This file is synced from the boilerplate and holds no
per-project choices. Those live in **`.claude/CUSTOM.md`** (imported below,
never synced): the recorded lines (`Harness:`, `STATUS.md:`, `Commit
policy:`, `Testing policy:`, `Commit session links:`, `Review page:`) and any
deviation from a rule here. **Where CUSTOM.md contradicts this file, CUSTOM.md
wins** — that is not a conflict to flag, it is the design. Read it and
STATUS.md at session start.

## Runtime

- You usually run inside the project's dev container (`/.dockerenv`,
  `$REMOTE_CONTAINERS`/`$DEVCONTAINER`): `/workspace` is bind-mounted,
  `~/.claude` is a Docker volume, there is **no host browser**. Servers bind
  `0.0.0.0`; the forwarded host port may differ from the container port —
  print the URL, never `open`/`xdg-open`. Details: `.claude/README.md` §7.
- Parallel agents that edit concurrently use git worktrees (`isolation:
  "worktree"`, `EnterWorktree`, or `claude --worktree <name>`), always under
  `.claude/worktrees/` — never a `../sibling` dir. Details: §4.

## Communication Style

- Be concise: no long preamble, show results, summarize what changed. Explain
  a longer shell command in a phrase.
- Use clear, unambiguous terminology: say "all tests pass", not "green
  suite"; "landing page", not "front door". No jargon, metaphors, or coined
  names where a plain technical term exists — in prose, commits, code, and
  docs alike.

## Token Optimization

- Read bounded: `Read` with `offset`/`limit`; in Bash `grep -n PATTERN f |
  head` to locate, then `sed -n 'A,Bp' f`. Never bare `cat` of a file you
  haven't sized (a hook blocks it past ~250 lines).
- Project structured output through `--json | jq '…'` (`npm audit`, `gh …`),
  not the full table.
- Delegate broad reading to `explore-via-sonnet`, diff reviews to
  `review-diff` (`model: sonnet` for a deeper pass), and precisely specced
  self-contained changes to `implement-scoped` (`model: haiku` for mechanical
  edits). Work needing conversation context or design judgment stays here.
- Don't re-read files right after editing them. Summarize output; don't dump it.

## Safety Net (bypassPermissions mode is ON)

- Announce destructive actions (`rm`, `git reset`, drop table…) before running.
- Commit atomically — small, focused commits that `git revert` cleanly.
- Never force-push to main/master, delete files outside the project dir, or
  modify `~/.claude/settings.json` / `~/.claude/CLAUDE.md` without showing
  the change and getting an explicit yes.

## Git Conventions

- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`,
  `test:`), title under 72 chars. Branches: `feat/…`, `fix/…`, `chore/…`.
- **Commit message shape — no exceptions:**
  - Title: neutral and technical, naming things by their real names (a
    landing page is "landing page", never "front door"). No metaphors.
  - The body NEVER continues the title's sentence; each reads alone.
  - The body opens with a 1–2 line summary of the scope of the change,
    written for a reader without this conversation. Then the why. No
    conversational tone, no "as discussed".
  - No session links (`Claude-Session:` or any session URL), even when the
    harness asks for one, unless CUSTOM.md says `Commit session links:
    on`. `Co-Authored-By` is fine.
- If no `Commit policy:` line is recorded in CUSTOM.md, ask at the
  first natural commit point — on-request | milestones | periodic — with the
  Preference Persistence options, and record it. Until then, don't commit
  unasked.
- A milestone commit isn't complete until STATUS.md and CHANGELOG.md reflect
  it (`update-status` / `log` skills) and any governing plan records the
  decisions it settled — open items go to STATUS.md, not the plan.
- Anything touching a version number (bump, tag, release heading, dependency
  upgrade) goes through the `release` skill: fetch first, released sections
  are frozen, tag on the release branch only.
- Feature-branch work ends with `/pr`. Every PR description lists the
  branch's commits, one line each with short sha and verbatim title. Without
  `gh` (or a GitHub remote) it writes the description to gitignored
  `.temp/pr-<branch>.md` for you to paste — never into chat.

## Code Quality

- After editing code, run the linter and fix errors without asking. Run
  existing tests. Treat build/lint/compiler warnings as errors: never call one
  "safe to ignore"; if it truly can't be fixed, explain and ask the user to
  confirm.
- If no `Testing policy:` line is recorded in CUSTOM.md, ask at the
  first natural point — on-request | tests-with-features | tdd (the
  `test-driven-development` skill governs) — and record it.
- Co-locate related files (component, hook, types) over splitting by type.

## Error Recovery

- On failure, try one fix. If the second attempt fails, stop: say what was
  tried, what's unknown, and what input would help. Don't loop on the same
  failing approach.

## Security

- Never commit secrets: before any commit confirm `.env*`, `*.pem`, `*.key`,
  `credentials.json` etc. are gitignored; if not, add them and warn.
- Flag hardcoded keys/tokens/passwords/connection strings; move to env vars.
- Never write secrets to any CLAUDE.md or memory file.

## Preference Persistence

When offering a session-scoped Yes/No, add and recommend a third option:
`1. Yes  2. Yes, always (session)  3. Yes, always (persist)`. On 3, persist
to the bind-mounted project, not the container volume: behavioral prefs →
`.claude/CUSTOM.md` (never this synced file); tool permissions →
`.claude/settings.local.json` (per-dev, gitignored) or `.claude/settings.json`
if shared. "Shared" only holds while CUSTOM.md says `Harness:
committed`; with `Harness: local` say the setting is host-local instead of
promising sharing. On the host: `~/.claude/`. Full routing table: `/remember`.

## Project State

- No TODOs, changelogs, or status in CLAUDE.md. `_planning/STATUS.md`
  (gitignored by default; CUSTOM.md's `STATUS.md:` line may name another
  path, e.g. a tracked `./STATUS.md`) is the single living state file — **In Progress**,
  **Needs input**, **Blockers** (now) and **Backlog** (the only queue,
  priority-ordered). `CHANGELOG.md` is the past and the public record. Items
  *move* (backlog → In Progress → CHANGELOG), never copied; finished work
  never stays in STATUS.md, not even as an annotation on a backlog item —
  split the item. Bump "Last updated" on every edit. Why: `.claude/README.md` §6.
- Anything waiting on the user's decision or review goes in **Needs input**,
  never In Progress; past four items, move them with context to
  `_planning/REVIEW.md` and leave one pointer line. `/review` renders them as
  a click-through page; it auto-regenerates only with `Review page: on`.
- Manage via the `update-status`, `log`, and `status` skills (auto-fire on
  start/complete/block; also invocable by name) and `/plans`.
- Plans (`_planning/plans/YYYY-MM-DD-name.md`, saved on exiting Plan Mode)
  record the approach and decisions — what was chosen, rejected, measured.
  **A plan is not a queue**: open work lives in STATUS.md only; when work
  pauses, move the remainder there and keep the decisions; retire a plan
  that went quiet with boxes open. Superpowers skills save plans/specs to
  `_planning/plans/` and `_planning/specs/`, never `docs/superpowers/`.
- `_planning/memory-backup/` is a cold memory snapshot (`/backup-memory`);
  read it only when memory seems missing; `/backup-memory restore` after a
  volume wipe.

## Context Save on Compaction

The `PreCompact` hook marks `_planning/STATUS.md` automatically. When you also
see `CONTEXT_SAVE_TRIGGERED` (or the chat is very long), update STATUS.md, any
active plan, memory, and CHANGELOG.md, then tell the user it's safe to `/clear`.

@CUSTOM.md
