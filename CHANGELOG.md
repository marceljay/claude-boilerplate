# Changelog

All notable changes to this boilerplate are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Bundled skills in `.claude/skills/`, vendored from Jesse Vincent's Superpowers
  collection (MIT, attribution in `.claude/skills/ATTRIBUTION.md`):
  `using-superpowers` (invoke a relevant skill before responding),
  `test-driven-development` (red-green-refactor), and `systematic-debugging`
  (root-cause-first). Only the Claude Code platform reference is vendored from
  `using-superpowers`; `/plugin install superpowers@…` gets the full upstream set.
  Surfaced in the root README and `/init`'s report — they auto-discover, no install.
- Two more vendored skills: `writing-plans` and `brainstorming`, **modified from
  upstream** — they *ask the user before starting* (upstream auto-fires brainstorming
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
