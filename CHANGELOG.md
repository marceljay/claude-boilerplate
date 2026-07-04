# Changelog

All notable changes to this boilerplate are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- `PreToolUse` guard hook (`.claude/hooks/block_destructive.py`) — the deny
  list is prefix-matched, so `rm -fr`, `rm -r -f`, and `git push -f` slipped
  past it. The hook tokenizes each Bash command (quote-aware, works in every
  permission mode incl. bypassPermissions) and blocks destructive intent in any
  spelling: recursive+force `rm` at protected paths, force-pushes to
  main/master, `git reset --hard`, `git clean -f`, destructive SQL via DB
  clients, `dd` to block devices, `mkfs`. Fails open on internal errors but
  logs them to `.claude/logs/hook_errors.log`.

### Changed

- `status-staleness-check.sh` (SessionStart) now has a second, sharper check:
  `STATUS_DRIFT` fires when In Progress is non-empty **and** commits have landed
  since STATUS.md was last modified — the signature of "finished but never
  cleared" — so it flags the very next session instead of waiting out the 7-day
  staleness window. `save-context.sh` (PreCompact) now *replaces* its previous
  compaction marker instead of appending, so markers no longer accumulate in
  STATUS.md.
- Subagents: `review-via-haiku`/`review-via-sonnet` (byte-identical except the
  `model:` line) merged into one `review-diff` agent — Haiku by default, with
  the Agent tool's per-invocation `model` override for a deeper Sonnet pass.
  New `implement-scoped` agent (Sonnet, override to Haiku for mechanical edits)
  implements precisely specced, self-contained changes: runs lint/tests on what
  it touched, returns a diffstat plus what it verified, stops and asks instead
  of guessing when the spec is ambiguous.
- Deny list: added the common variants (`rm -fr`, `git push -f`) as free
  tripwires; dropped `Bash(drop table:*)`, which could never match (SQL goes
  through a client binary, not a bash prefix — the hook covers it now).

- Project-state commands `/update-status`, `/log`, `/status`, `/backlog` are now
  **skills** (`.claude/skills/<name>/SKILL.md`) so Claude invokes them itself when
  a work item starts, completes, or blocks — fixes finished items lingering in
  STATUS.md because nobody typed the command. Still invocable by name. The
  `update-status` skill also cleans up PreCompact `<!-- context compacted -->`
  markers, and CLAUDE.md now ties state upkeep to milestone commits ("a milestone
  commit isn't complete until STATUS.md/CHANGELOG reflect it").

### Added

- `docs-updater` subagent (`.claude/agents/docs-updater.md`) — checks whether
  docs need updating by diffing against the last commit that touched them
  (not just the latest commit), and edits only if the change is user-facing;
  skips silently otherwise. `/docs` now tries it first before falling back to
  its manual checklist.
- `SubagentStop` hook (`.claude/hooks/log_subagent.py`) logs every subagent
  run — task, model, token usage, result summary — to
  `.claude/logs/subagents.jsonl` (gitignored: may contain tool output/secrets).
  `.claude/scripts/subagent_summary.py` tabulates the log by model and agent
  type to see where subagent usage is going.
- Bundled skills in `.claude/skills/`, vendored from Jesse Vincent's Superpowers
  collection (MIT, attribution in `.claude/skills/ATTRIBUTION.md`):
  `using-superpowers` (invoke a relevant skill before responding),
  `test-driven-development` (red-green-refactor), and `systematic-debugging`
  (root-cause-first). Only the Claude Code platform reference is vendored from
  `using-superpowers`; `/plugin install superpowers@…` gets the full upstream set.
  Surfaced in the root README and `/init`'s report — they auto-discover, no install.
- Two more vendored skills: `writing-plans` and `brainstorming`, **modified from
  upstream** — they _ask the user before starting_ (upstream auto-fires brainstorming
  and hard-gates all implementation until a design is approved), save to
  `_planning/plans/` and `_planning/specs/` instead of `docs/superpowers/`, and the
  browser-based "visual companion" is dropped (no host browser in the dev container).
  `/init` now scaffolds `_planning/specs/`; modifications documented in ATTRIBUTION.md.
- First-run onboarding: a `SessionStart` hook (`first-run-check.sh`) detects an
  un-detached boilerplate copy — by the dev container still carrying the default
  `"name": "Claude Boilerplate Repo"` — and reminds the user to run `/init`
  (which offers to remove the template README/LICENSE and reset git history).
  `/init` and `scripts/new-project.sh` rename the container to the project, which
  also turns the nudge off; the README advises renaming it.
- Docs: how to enter Plan Mode (Shift+Tab / `--permission-mode plan`) in the
  root README; a "slash commands vs. Skills vs. subagents" comparison in
  `.claude/README.md` §3.
- `scripts/new-project.sh` — one-shot detach script for new projects: renames
  README → BOILERPLATE.md, removes the boilerplate LICENSE, resets state files,
  re-inits git (default; `--keep-git` retains history), then deletes itself.
  `/init` offers to run it when the copy is still undetached.
- `/backup-memory` command — mirrors auto-memory (committed) and raw session
  transcripts (gitignored) into `_planning/` as a failsafe against Docker
  volume loss.
- Per-project commit policy: CLAUDE.md now asks once
  (on-request / milestones / periodic) and records the answer; `/init` asks
  during scaffolding. This repo: milestones.
- `.claude/README.md` — plain-language guide to the harness (hooks, subagents,
  commands, memory, state files); no prior Claude Code experience assumed.
- `explore` and `review` subagents (`.claude/agents/`) to keep heavy reading and
  diff review out of the main context window.
- Real `PreCompact` hook script (`.claude/hooks/save-context.sh`) that writes a
  timestamped marker to `STATUS.md` before auto-compaction.
- Root `README.md` describing the boilerplate and how to adopt it.
- Cross-stack permissions (Python, Rust, Go, Make, pnpm/yarn) in `settings.json`.
- `LICENSE` (MIT).
- Dev Container section in `README.md` explaining what dev containers are and
  documenting the firewall allowlist and container settings.

### Fixed

- Container-awareness for dev servers/ports: Claude now knows it runs in the
  dev container (new `CLAUDE.md` Runtime note), `/dev` binds `0.0.0.0`, runs the
  server in the background, and surfaces the forwarded URL instead of opening a
  browser; `devcontainer.json` documents the dynamic port-forward that lets
  parallel containers coexist; README §7 explains bind-mount vs volume and ports.
- Memory-location docs were contradictory: README/`/remember` implied a repo
  `memory/` folder, but live memory lives in
  `$CLAUDE_CONFIG_DIR/projects/<repo>/memory/` (a Docker volume in dev
  containers), with only the `_planning/memory-backup/` snapshot in the repo.
  Clarified across `.claude/README.md` and `/remember`. Also corrected §4's
  stale "ships no agents yet" note (`explore`/`review` do ship).

### Changed

- `subagent_summary.py` now reports all-time totals instead of a `--last`/`--all`
  windowed view (dropped both flags): the by-model, by-agent-type, and grand
  totals always cover every logged session. Added a "Last N individual
  invocations" table (default 10, `--invocations N` to change it) showing each
  run's timestamp, agent type, model, token breakdown, and cost, most recent
  first. Entries with no recorded token usage (e.g. interim SubagentStop
  events with `model: null`) are now skipped in totals and the invocation
  list, with a count of how many were skipped.
- Renamed the `explore` subagent to `explore-via-sonnet` and pinned it to the
  `sonnet` model (previously ran on the default model) — it's a read-only
  fan-out search agent, so the cheaper/faster model suits it. Updated
  references in `README.md`, `.claude/README.md`, and `CLAUDE.md`.
- CLAUDE.md now routes Superpowers plan/spec output to `_planning/plans/` and
  `_planning/specs/` instead of the plugin's default `docs/superpowers/` — so a
  downstream project that installs the full Superpowers plugin keeps planning docs
  in the boilerplate's `_planning/` convention.
- `/remember` (and CLAUDE.md's Preference Persistence) are now dev-container-aware:
  `~/.claude/` is a per-container volume there (lost on rebuild, not shared across
  projects), so "global" prefs now persist to the bind-mounted `/workspace` —
  permissions → `.claude/settings.local.json` (per-dev) or `.claude/settings.json`
  (shared), behavioral prefs → project `.claude/CLAUDE.md`. Host behavior unchanged.
- `/init` now asks whether to commit or gitignore the `.claude/` and
  `.devcontainer/` dirs before the first commit — committing shares the setup,
  but on a public repo it exposes your instructions/workflow/permissions.
- Clarified the "Be concise" communication rule so it isn't read as "never
  explain" — keep preamble short, but still explain longer shell commands.
- Reworked project-state files: **`_planning/STATUS.md` is now the single living
  state file** — In Progress + Blockers (now) and a `# Backlog` section (future,
  the only queue); `CHANGELOG.md` stays the past (and the public record). Items
  move between sections/files, never copied. The backlog was merged in from the
  former separate `_planning/backlog.md` to fight staleness: keeping the queue
  beside "In Progress" means you can't grab the next item without seeing (and
  fixing) what's stale.
- STATUS.md is now **gitignored by default** (private working state — your
  in-progress work and TODOs aren't pushed to a possibly-public remote); `/init`
  asks per-project whether to make it public instead.
- A `SessionStart` hook (`status-staleness-check.sh`) prints STATUS.md's age at the
  top of a session once its "Last updated" date is >7 days old (override with
  `STATUS_STALE_DAYS`); `/status` also flags it. `/backlog`, `/status`,
  `/update-status`, `/init`, the `PreCompact` save hook, and `scripts/new-project.sh`
  were all updated for the new location. Dropped STATUS.md's "Up Next"/"Recently
  Completed" sections; `/log` only asks about releases when the user hints at one.
  (One-tense split field-tested in shark-attack-atlas, 2026-06-11; consolidated and
  made private after STATUS.md kept going stale.)
- Trimmed `CLAUDE.md` ~47% (965 → 514 words); moved verbose procedures to `/init`
  and `.claude/README.md`, named the new subagents.
- Made `/cleanup`, `/dev`, `/deploy`, and `/init` stack-detecting instead of
  npm-only.
- Collapsed redundant `settings.json` rules (granular `git`/`npm run` entries
  already covered by `git:*` / `npm:*`).

### Fixed

- Corrupted `editor.formatOnSave` key in `.devcontainer/devcontainer.json` that
  made the file invalid JSON.
- `PreCompact` hook was a no-op `echo`; it now runs a real save script.

### Chore

- Initialized git and gitignored `.DS_Store` and `.claude/settings.local.json`
  (per-developer overrides, not part of the template).
