# Changelog

All notable changes to this boilerplate are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- `scripts/new-project.sh` — one-shot detach script for new projects: renames
  README → BOILERPLATE.md, removes the boilerplate LICENSE, resets state files,
  optionally re-inits git (`--fresh-git`), then deletes itself.
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

### Changed
- State files now own one tense each (STATUS.md = now, `_planning/backlog.md` =
  future, CHANGELOG.md = past); items move between files, never copied.
  Dropped STATUS.md's "Up Next"/"Recently Completed" sections; `/log` only asks
  about releases when the user hints at one. (Field-tested in
  shark-attack-atlas, 2026-06-11.)
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
