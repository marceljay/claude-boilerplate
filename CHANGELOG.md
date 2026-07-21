# Changelog

All notable changes to this boilerplate are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- `.devcontainer/STACKS.md` §"Active scanning (Socket)" — documents
  [Socket](https://socket.dev) as the opt-in *detective* counterpart to the
  passive gates already in §Supply-chain hardening (age rule, no install
  scripts, lockfiles): it analyzes what a package's code actually does, so a
  malicious release is caught before a CVE exists. Investigated rather than
  installed, because three findings argue against baking it into the image:
  it's a **service, not a local scanner** (server-side analysis, needs
  `SOCKET_CLI_API_TOKEN`, uploads your manifest to a third party; ~1K
  scans/month free, free for qualifying OSS), the **container firewall blocks
  it** by default, and it's a 21 MB global npm install that most projects
  built on this boilerplate won't want. `init-firewall.sh` now carries a
  commented-out `api.socket.dev`/`socket.dev` block so enabling it is
  uncomment-and-rebuild rather than research-from-scratch. Also records that
  Socket is **not npm-only** despite the reputation (PyPI, Go, Maven/Gradle,
  Cargo, NuGet, RubyGems, Composer), while its CLI *is* npm-distributed — so
  a Rust- or Go-only project still pulls Node in to run it. The published
  tarball has no install scripts, so it coexists with the repo's
  `ignore-scripts=true`.

- Status line showing account rate-limit usage
  (`.claude/scripts/usage-statusline.sh` + a `statusLine` entry in
  `.claude/settings.json`) — prints the 5-hour and 7-day usage windows with
  each window's reset time in local time, e.g.
  `5h 23% · resets 17:00 │ 7d 41% · resets Thu 17:00`. Costs **no tokens**:
  status lines run locally and never enter the model context (unlike
  `SessionStart`/`UserPromptSubmit` hooks, whose stdout is injected). The data
  comes from `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`
  on the status-line stdin JSON, which only the status line receives — a
  regular hook can't see it. Present for Claude.ai Pro/Max after the first
  API response; before that, and on API-key auth, it falls back to context
  usage. Timestamps are formatted with `date` rather than jq's
  `strflocaltime` (the container ships jq 1.6, which lacks it). Timezone is
  read from `$TZ` so the shared script hardcodes nobody's zone — set it
  per-machine in the gitignored `.claude/settings.local.json`
  (`"env": { "TZ": "Area/City" }`) or via the host `TZ` the devcontainer
  already forwards.

- `.claude/README.md` §8 "Boilerplate detection & lifecycle" — documents how
  the harness tells the boilerplate's own dev repo apart from a copy made
  from it, which was previously implicit across three files. Covers the two
  signals and why one ships and one doesn't (the **committed** container name
  `"Claude Boilerplate Repo"`, inherited by every copy as the durable "not set
  up yet" flag, vs. the **gitignored** `.boilerplate-dev` marker that clones
  never receive, identifying the origin), a table of the three consumers
  (`first-run-check.sh`, `new-project.sh`, `/init`) with their behaviour with
  and without the marker, and the flows including the edge cases: a fresh
  clone of the dev repo (marker is gitignored, so it must be re-created with
  `touch .boilerplate-dev` — the design's one rough edge), copies made without
  `new-project.sh` (degit / "Use this template" / manual), copies where nobody
  renames the devcontainer (the nudge persists by design), and harness
  installs into an existing codebase. `/init` step 0 now notes that its
  `.boilerplate-dev` branch is normally unreachable but is the only guard
  stopping a stray `/init` from renaming the container and silently breaking
  first-run detection downstream.

- `PreToolUse` guard hook (`.claude/hooks/block_destructive.py`) — the deny
  list is prefix-matched, so `rm -fr`, `rm -r -f`, and `git push -f` slipped
  past it. The hook tokenizes each Bash command (quote-aware, works in every
  permission mode incl. bypassPermissions) and blocks destructive intent in any
  spelling: recursive+force `rm` at protected paths, force-pushes to
  main/master, `git reset --hard`, `git clean -f`, destructive SQL via DB
  clients, `dd` to block devices, `mkfs`. Fails open on internal errors but
  logs them to `.claude/logs/hook_errors.log`.

- `/socratic` command — question instead of answer, on request. Default mode
  stress-tests a design/decision (assumptions, failure modes, discarded
  alternatives, one question at a time, no solutions until asked);
  `/socratic teach` tutors the user toward their own answer. Deliberately a
  command, not a skill: only the user knows when they want to be questioned
  instead of answered, so it must never auto-fire — and commands cost no
  always-on tokens.

- `scripts/sync-harness.sh` — installs this repo's harness into an existing
  codebase, or refreshes a sibling project's stale copy (run from the **host**;
  a dev container can't see sibling dirs). **Install mode** (target has no
  `.claude/`; a target directory that doesn't exist yet is created, so the
  script also bootstraps a brand-new project dir): one confirmation, then
  copies `.claude/` + `.devcontainer/` and
  nothing else — `.git`, code, README untouched — stripping this repo's
  recorded commit/testing-policy lines from the copied CLAUDE.md so `/init`
  asks the adopting project fresh; ends with next steps (reopen in container,
  run `/init` to gap-fill). **Replace mode** (`--replace`) swaps out an
  unwanted existing harness (foreign/hand-rolled, or conventions worth
  abandoning): backs up the target's `.claude/` + `.devcontainer/` to a
  timestamped tar.gz at the project root, removes them, then proceeds as a
  fresh install — overwriting sloppy recorded policies wholesale (for a
  single file, refresh mode's diff prompt already suffices). **Refresh
  mode** mirrors the pure-harness dirs (`.claude/{commands,skills,agents,
  hooks,scripts}`, `.claude/README.md`, `.devcontainer/STACKS.md`), listing
  and confirming any deletions of target-only files; files that usually carry
  per-project edits (`init-firewall.sh` custom domains, `devcontainer.json`
  name/features, `Dockerfile` toolchains, `CLAUDE.md` policies,
  `settings.json` permissions) get a diff and an overwrite prompt, defaulting
  to keep. Never touches `settings.local.json`, logs, or `_planning/`. No
  rsync dependency (tar/find/comm) so it runs on a stock macOS host.

- `.devcontainer/STACKS.md` — per-stack recipes (Python, Go, Rust, Java, Ruby)
  for making the Node-first container serve other stacks: toolchain install
  (build time, firewall-exempt), the *exact* firewall domains (package managers
  need an index host **and** a download host — missing the second hangs
  installs silently, e.g. `pypi.org` without `files.pythonhosted.org`), a
  rebuild, and an end-to-end verification install. Outcome of the 2026-07-07
  stack-agnosticism review, which established empirically that the container
  was Node-only in practice (no pip/ensurepip; pypi.org and even
  deb.debian.org firewalled) while the docs claimed four-stack support.
  Automation of the recipe via `/init` is spec'd in the backlog, deferred
  until a real non-Node project exists to test against.

### Fixed

- `/init` no longer skips an existing `.gitignore` wholesale — the universal
  security/planning entries (`.env*`, `*.pem`, `*.key`, transcripts backup,
  the private-by-default `_planning/STATUS.md`) are now *ensured*: missing
  ones are appended under an `# Added by /init` header, equivalent existing
  patterns count as present, and nothing already there is touched. Stack
  entries (`node_modules/` etc.) are still only written on fresh creation.
  (Item (b) of the 2026-07-04 dry-run findings; (a), (c), (d) remain in the
  backlog.)

### Removed

- `/deploy` command — it assumed deploys are local hosting-CLI runs (Vercel/
  Netlify-centric, no CI-driven path, no library publishing), would be blocked
  by the container's own firewall anyway, and its strongest signal (an explicit
  deploy script/target) was checked last. Removed rather than patched; a
  proper stack-agnostic rewrite is spec'd in the backlog.
- Stale plan `_planning/plans/2026-06-11-boilerplate-handoff.md` — its work
  shipped long ago but its checkboxes read 0/4 done, inviting a future session
  to redo it. The past lives in CHANGELOG.md and git history, not in plans.

### Added

- Supply-chain hardening (2026-07-15). Root `.npmrc` with
  `ignore-scripts=true` (no install-time code execution — the main npm
  attack vector; caveat comments cover native-build packages and own
  pre/post hooks) and `save-exact=true`. New **Supply-chain hardening**
  section in `.devcontainer/STACKS.md`: the never-install-day-zero
  principle (~7-day minimum release age), lockfile + frozen-CI baseline,
  per-ecosystem guidance (pnpm `minimumReleaseAge` as the strongest native
  option, yarn `enableScripts: false`, Go's structural safety, cargo
  `--locked`/`cargo-deny`/`cargo-vet`, uv `exclude-newer`), and
  Renovate/Dependabot cooldown as the universal age gate. `sync-harness.sh`
  now carries `.npmrc` in its ask-first group.

### Changed

- `/dev` accepts a port (`/dev 5173`): explicit argument > recorded
  `Dev port:` line in the project CLAUDE.md > stack detection. The first
  successful run on an explicitly requested port records it as that one-liner
  (the `Commit policy:` pattern), making it the default for future runs;
  detected/default ports are never recorded. The port is passed via the dev
  command's own flag, not by editing config files.
- README's Getting Started now has two explicit paths: **A** — new project
  seeded from this repo (detach via `new-project.sh`, then `/init`); **B** —
  existing codebase adopts the harness via `sync-harness.sh` install mode,
  with a warning not to copy the whole repo (README/LICENSE/git history would
  collide). `/init` step 0 recognizes the adopted case (no `.boilerplate-dev`,
  no `new-project.sh`, real code + history present): nothing to detach, the
  run is pure gap-filling.
- Honest stack claim: README now distinguishes the stack-agnostic **harness**
  from the Node-first **container** and links STACKS.md; `/init` warns when it
  detects a non-Node stack inside the container instead of scaffolding into a
  dead end; `init-firewall.sh`'s allowlist is now a commented, grouped
  `allowed_domains` array (harness / Node / VS Code / additional stacks) noting
  that edits require a rebuild because the image bakes the script in.
- README's Dev Container section now states the platform limit up front: dev
  containers are Linux, so native iOS/macOS work (Xcode, simulators, signing)
  can't happen inside one — use the `.claude/` harness on the Mac host instead
  (it's portable; only the container's isolation/firewall is lost).
- Resolved the TDD-vs-CLAUDE.md contradiction with a **per-project testing
  policy**, mirroring the commit policy: `Testing policy: on-request |
  tests-with-features | tdd`, asked once (also by `/init`) and recorded as a
  CLAUDE.md one-liner. The vendored `test-driven-development` skill now fires
  only under the `tdd` policy or on explicit request instead of on every
  feature/bugfix; CLAUDE.md's blanket "don't write new tests unless asked"
  became the `on-request` option (and this repo's recorded policy).
  `using-superpowers` was toned down: "invoke a clearly relevant skill before
  starting, user instructions always win" replaces upstream's "1% chance →
  ABSOLUTELY MUST invoke before ANY response" dispatch rule, red-flags table,
  and brainstorm-before-plan-mode push, which kept dragging rigid skills into
  tasks that hadn't opted in. Both modifications documented in ATTRIBUTION.md.
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

- `.boilerplate-dev` marker (gitignored, so clones/copies never inherit it)
  identifies the boilerplate's own dev repo: `first-run-check.sh` stops nagging
  every session, `scripts/new-project.sh` refuses to detach (it would reset the
  dev repo's history), and `/init` skips the detach offer and the container
  rename (the default container name is the first-run detection signal and
  must keep shipping). Recreate after a fresh clone: `touch .boilerplate-dev`.
- Stale claim in `.claude/README.md` that the `PreCompact` hook "only does
  `echo`" — it has run a real save script for a while.
- The boilerplate's own `.gitignore` was missing the secret-file entries its
  own security rule and `/init` template mandate (`.env*`, `*.pem`, `*.key`,
  `credentials.json`, `Thumbs.db`) — found by dry-running `/init` against the
  repo. Added them.
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

- Subagent log: zero-token relic rows are gone. The hook no longer logs
  interim SubagentStop events (parent polling a still-running agent — no usage
  data, pure noise), while an *unreadable* transcript still logs as zeros on
  purpose, since a streak of those is what exposed the 45b06df payload-field
  regression. `subagent_summary.py --prune` rewrites the log to drop relics
  from older hook versions (30 removed here); its docstring documents both
  causes.
- Subagent log/summary: the misleading `total_tokens` field (really just
  uncached input + output — it excluded cache reads/writes, the bulk of most
  runs' volume and ~2/3 of their cost) is renamed to `fresh_tokens`;
  `subagent_summary.py` reads both names, relabels the column "Fresh", and
  prints a short explainer of the per-turn cache mechanics and pricing
  multipliers so the numbers can't be misread as totals.
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
