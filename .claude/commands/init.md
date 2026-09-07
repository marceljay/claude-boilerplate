# Initialize Project Structure

Scaffold the standard file structure for a new project.

## Steps

0. **Guard:** if a `.boilerplate-dev` file exists at the repo root, this is the
   boilerplate's own development repo — do NOT offer to detach and skip the
   container rename in step 3 (the default name is the first-run detection
   signal and must keep shipping to copies). Run only the steps that fill
   genuine gaps. (This branch normally never fires — you'd rarely run `/init`
   in the boilerplate's own repo — but it's the only thing stopping a stray
   run from renaming the container and breaking downstream detection. See
   `.claude/README.md` §8 for the full origin-vs-copy flow.)

   Otherwise, if this copy hasn't been detached from the boilerplate yet
   (`scripts/new-project.sh` still exists), offer to run it first — it renames
   the boilerplate's README to `BOILERPLATE.md`, deletes LICENSE, resets the state files, drops the
   boilerplate's git history (default; `--keep-git` retains it), and deletes
   itself. Example:

   ```sh
   bash scripts/new-project.sh -y
   ```

   If neither marker nor script exists but the project has real code and git
   history, the harness was likely installed into an existing codebase
   (`scripts/sync-harness.sh` install mode) — there's nothing to detach;
   this run is pure gap-filling. Expect existing files: merge the
   `.gitignore` (step 2), leave README/CHANGELOG/code alone unless missing,
   and mind the non-Node stack check in step 1.

1. Detect project context:
   - Determine the tech stack and project name from whatever manifest exists:
     `package.json` (Node), `pyproject.toml`/`requirements.txt` (Python),
     `Cargo.toml` (Rust), `go.mod` (Go), or the directory name as a fallback
   - Check what already exists — don't overwrite existing files (exception:
     an existing `.gitignore` is merged into, never skipped — see step 2)
   - **Non-Node stack in the dev container?** The container ships only the
     Node toolchain, and its firewall passes only npm's registry — for any
     other stack, installs fail or hang until the recipe in
     `.devcontainer/STACKS.md` is applied (toolchain + firewall domains +
     rebuild + verify). Tell the user this now, before scaffolding continues,
     so day one doesn't end at a silent dead end.

2. Create the following files if they don't exist:

   **`.gitignore`** — universal base (applies to any stack):

   ```
   .env*
   *.pem
   *.key
   .DS_Store
   Thumbs.db

   # Raw session transcripts — host-disk backup only, may contain tool output/secrets
   _planning/transcripts-backup/

   # Working status + backlog — private by default (see the STATUS.md visibility ask below)
   _planning/STATUS.md

   # Git worktrees Claude Code creates (claude --worktree, EnterWorktree, subagent
   # isolation) — checkouts, not source; kept in-repo so the dev container sees them
   .claude/worktrees/
   ```

   **If `.gitignore` already exists, do NOT skip it** — the universal base
   entries above are required either way. Check each one and append only the
   missing ones at the end of the file, under a short header
   (`# Added by /init — security + planning`), leaving the existing content
   untouched. An entry counts as present if an equivalent pattern already
   covers it (e.g. an existing `.env*` covers `.env.local`; `*.key` covers
   `private.key`). The `_planning/STATUS.md` line is governed by the
   visibility ask below in both the create and merge cases.

   Then add entries for the **detected stack**, e.g.:
   - Node: `node_modules/`, `dist/`, `.next/`, `.vercel/`
   - Python: `__pycache__/`, `*.pyc`, `.venv/`, `.pytest_cache/`, `*.egg-info/`
   - Rust: `target/`
   - Go: built binaries / `bin/`

   (Stack entries only when creating the file fresh — a project with an
   existing `.gitignore` almost certainly has them already; don't append
   guesses. If an obvious gap exists, mention it instead of editing.)

   **Ask about the Claude/dev-tooling dirs** (skip if the project CLAUDE.md
   already has a `- Harness:` line). The `.claude/` harness (your
   CLAUDE.md, commands, agents, hooks, permissions) and `.devcontainer/` config
   are tracked by default — committing them shares the setup with collaborators,
   but on a **public** repo it also exposes your instructions, workflow, and
   permission rules to anyone. Ask the user which they want **before the first
   commit** (this is the moment to decide, since `/init` runs on a fresh git
   history), then **record the answer** in the project CLAUDE.md, in the
   Preference Persistence section, as `- Harness: committed (this repo).` or
   `- Harness: local (this repo).` — it's the baton later sessions and
   `/remember` read to know whether "shared" means anything here:
   - **Commit them (default, recommended for teams/private repos)** — leave them
     tracked; the harness travels with the repo.
   - **Keep them local (recommended if the repo is/_will be_ public and the setup
     is personal)** — add to `.gitignore`:
     ```
     # Claude Code harness + dev container — local only, not shared/published
     .claude/
     .devcontainer/
     ```
     **Say the consequence out loud:** from then on nothing under `.claude/`
     reaches a clone, another machine, or a teammate — CLAUDE.md preferences,
     `settings.json` permissions, hooks, and any harness fixes stay on this
     machine, and `/remember`'s "shared" targets are local too.
     Note this also keeps them out of collaborators' clones. (`settings.local.json`
     is already ignored regardless.) If the dirs were already committed in a prior
     history, also run `git rm -r --cached .claude .devcontainer` so the ignore
     takes effect.

   **Ask about STATUS.md visibility** (skip if the project CLAUDE.md already has
   a `- STATUS.md:` line). `_planning/STATUS.md` holds the living
   status **and** the backlog — i.e. what you're working on and what's planned. The
   base `.gitignore` above keeps it **private by default**, which is usually what you
   want on a public repo (don't broadcast your in-progress work and TODOs). Ask the
   user, then record the answer in the project CLAUDE.md's Project State section
   as `- STATUS.md: private (this repo).` or `- STATUS.md: public (this repo).`:
   - **Private (default)** — leave the `_planning/STATUS.md` ignore line in place.
   - **Public** — the team should see status/backlog in the repo (a shared private
     repo, or you _want_ a visible roadmap): **remove** the `_planning/STATUS.md`
     line from `.gitignore` so it's committed. (`CHANGELOG.md` is committed either
     way — the shipped history is always public.)

   **`.gitattributes`**:

   ```
   * text=auto
   ```

   **`_planning/STATUS.md`** — the single living state file: present (In Progress,
   Needs input, Blockers) **and** future (the Backlog queue). Past → `CHANGELOG.md`. Gitignored
   by default (see the visibility ask above):

   ```markdown
   # Project Status

   Last updated: YYYY-MM-DD

   ## In Progress

   _None_

   ## Needs input

   _None_

   ## Blockers

   _None_

   ---

   # Backlog

   _The only queue of future work, priority-ordered. Top High-Priority item = next up._

   ## High Priority

   - Initial project setup

   ## Medium Priority

   ## Low Priority / Ideas
   ```

   **`CHANGELOG.md`**:

   ```markdown
   # Changelog

   All notable changes to this project are documented here.

   ## [Unreleased]

   ### Added

   - Initial project setup
   ```

   **`README.md`** — with:
   - Project name (from package.json or directory name)
   - Brief description (ask user if not obvious)
   - Tech stack
   - Setup/install instructions for the detected stack (`npm install`,
     `pip install -r requirements.txt`, `cargo build`, `go mod download`, …)
   - Development commands (`npm run dev`, `make dev`, `cargo run`, …)
   - Deployment info if detectable

   **`_planning/`** directory with:
   - `STATUS.md` — the living state file from above (gitignored by default)
   - `plans/` — empty directory (create with a `.gitkeep`); the `writing-plans`
     skill saves here
   - `specs/` — empty directory (create with a `.gitkeep`); the `brainstorming`
     skill saves design/spec docs here

   (The backlog is **not** a separate file — it's the `# Backlog` section of
   `_planning/STATUS.md`. Keeping the queue beside "In Progress" is what stops it
   going stale.)

   **`CLAUDE.md`** — if it doesn't exist, create a starter:

   ```markdown
   # Project Name

   Brief description.

   ## Commands

   <!-- Fill in the detected stack's commands -->

   - Dev: `npm run dev` / `make dev` / `cargo run`
   - Build: `npm run build` / `make build` / `cargo build`
   - Lint: `npm run lint` / `ruff check` / `cargo clippy`

   ## Architecture

   <!-- Add project structure and key patterns here -->

   ## Current Status

   See `_planning/STATUS.md` for current work and `CHANGELOG.md` for completed milestones.
   ```

   If CLAUDE.md already exists, just ensure it has the STATUS.md/CHANGELOG.md reference line.

   Then ask the user which commit policy they want — on request only /
   automatically at milestones / periodically — and record it in CLAUDE.md as
   `Commit policy: on-request | milestones | periodic`.

   Also ask for a testing policy and record it as
   `Testing policy: on-request | tests-with-features | tdd`:
   - **on-request** — no new tests unless asked (fits prototypes, scripts, config)
   - **tests-with-features** — new behavior gets tests alongside it (fits
     long-lived apps)
   - **tdd** — failing test first; activates the `test-driven-development`
     skill (fits projects with critical core logic)

   Ask whether commit messages may carry a Claude session link (skip if the
   project CLAUDE.md already has a `- Commit session links:` line). Claude
   Code appends a `Claude-Session: https://claude.ai/code/session_…` trailer
   when the harness requests it; the link is tied to one account, goes stale,
   and is noise in `git log` for everyone else, so the default is **off**.
   Record the answer as `- Commit session links: off (this repo).` or
   `- Commit session links: on (this repo).` under Git Conventions.

   Ask whether Claude should keep a **review page** up to date (skip if the
   project CLAUDE.md already has a `- Review page:` line). Items waiting on the
   user's decision live in STATUS.md's Needs input section (overflowing to
   `_planning/REVIEW.md`); `/review` renders them as a click-through page with
   Approve / Needs change / Reject per item. With `on`, the `update-status`
   skill regenerates that page itself whenever Needs input changes — one extra
   tool call per status edit; with `off` (default) only `/review` builds it.
   Record as `- Review page: off (this repo).` or `- Review page: on (this repo).`
   under Project State.

   Finally, **ask whether to enable Socket supply-chain scanning** — only if
   the project uses npm/pnpm/yarn, since those are the managers Socket's
   wrappers front. Ask rather than install: it needs an API token, and it
   uploads the dependency manifest to a third party, which is not a call to
   make on someone's behalf. Present it as:
   - **Skip (default)** — the passive gates still apply (`.npmrc`
     `ignore-scripts`, lockfiles, the age rule). `.claude/hooks/socket_scan.py`
     stays inert; nothing to undo.
   - **Enable** — then do all four, in order, and say so:
     1. `npm install -g socket@<pinned version>`
     2. have the user get a token at <https://socket.dev> (free tier; free for
        qualifying open source) and set it in the gitignored
        `.claude/settings.local.json` under `"env"` as `SOCKET_CLI_API_TOKEN`
        — never in `settings.json`, `CLAUDE.md`, or any committed file
     3. uncomment the two Socket domains in `.devcontainer/allowed-domains.txt`
        and tell them a **container rebuild** is required — until then every
        `socket` call fails at the network layer
     4. confirm the hook is live: with the token set and `socket` on PATH,
        `npm install <pkg>` is blocked in favour of `socket npm install <pkg>`
   Background and the age-gate exemption: `.devcontainer/STACKS.md`
   §Active scanning (Socket).

3. Rename the dev container to this project (skip if `.boilerplate-dev` exists —
   see step 0). If `.devcontainer/devcontainer.json`
   still has `"name": "Claude Boilerplate Repo"` (the boilerplate default),
   replace it with the project name. This is also the signal the first-run
   SessionStart hook uses to detect an un-detached copy, so renaming it stops
   that nudge. (`scripts/new-project.sh` already does this on detach; do it here
   for copies that skipped the script.)

   **Ask about the shell shortcuts' permission mode.** `cc`/`ccc`/`ccr`/`ccw`
   (`.devcontainer/claude-harness.zsh`) append `CLAUDE_SHORTCUT_FLAGS` from
   `devcontainer.json`'s `containerEnv`, empty by default. Skip the ask if it
   is already non-empty. Otherwise explain in two sentences and ask:
   - **Skip permission prompts in the shortcuts (recommended in the
     container)** — the sandbox is the guardrail here: default-deny firewall,
     only `/workspace` mounted. Plain `claude` still prompts, and nothing
     leaks to a host session. On yes, set the value to the permissions-bypass
     flag (`claude --help` lists it; it starts with `--dangerously`). The
     permission system may refuse to let you write that flag — if so, don't
     work around it: give the user the exact one-line edit to make in
     `devcontainer.json` themselves.
   - **Keep prompts** — leave it empty; the shortcuts behave like `claude`.
   Either way, note that `containerEnv` applies on the next **rebuild**;
   until then `export CLAUDE_SHORTCUT_FLAGS=…` in `~/.zshrc` bridges it.

4. Initialize git if not already a repo (`git init`).

5. Report what was created, listing each file. Also point out the **bundled skills**
   in `.claude/skills/` (`test-driven-development`, `systematic-debugging`,
   `using-superpowers`, `writing-plans`, `brainstorming`): they need no install —
   Claude Code auto-discovers them and invokes the matching one on its own.
   `writing-plans`/`brainstorming` save to `_planning/plans/` and `_planning/specs/`
   and ask before starting; `test-driven-development` activates only under
   `Testing policy: tdd`. Mention they can delete any folder they don't want,
   and that the full upstream set is available via the Superpowers plugin
   instead. See `.claude/skills/ATTRIBUTION.md`.

---
