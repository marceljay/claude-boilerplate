# Initialize Project Structure

Scaffold the standard file structure for a new project.

## Steps

0. If this copy hasn't been detached from the boilerplate yet
   (`scripts/new-project.sh` still exists), offer to run it first — it removes
   the boilerplate's README/LICENSE, resets the state files, drops the
   boilerplate's git history (default; `--keep-git` retains it), and deletes
   itself. Example:
   ```sh
   bash scripts/new-project.sh -y
   ```

1. Detect project context:
   - Determine the tech stack and project name from whatever manifest exists:
     `package.json` (Node), `pyproject.toml`/`requirements.txt` (Python),
     `Cargo.toml` (Rust), `go.mod` (Go), or the directory name as a fallback
   - Check what already exists — don't overwrite existing files

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
   ```
   Then add entries for the **detected stack**, e.g.:
   - Node: `node_modules/`, `dist/`, `.next/`, `.vercel/`
   - Python: `__pycache__/`, `*.pyc`, `.venv/`, `.pytest_cache/`, `*.egg-info/`
   - Rust: `target/`
   - Go: built binaries / `bin/`

   **Ask about the Claude/dev-tooling dirs.** The `.claude/` harness (your
   CLAUDE.md, commands, agents, hooks, permissions) and `.devcontainer/` config
   are tracked by default — committing them shares the setup with collaborators,
   but on a **public** repo it also exposes your instructions, workflow, and
   permission rules to anyone. Ask the user which they want **before the first
   commit** (this is the moment to decide, since `/init` runs on a fresh git
   history):
   - **Commit them (default, recommended for teams/private repos)** — leave them
     tracked; the harness travels with the repo.
   - **Keep them local (recommended if the repo is/*will be* public and the setup
     is personal)** — add to `.gitignore`:
     ```
     # Claude Code harness + dev container — local only, not shared/published
     .claude/
     .devcontainer/
     ```
     Note this also keeps them out of collaborators' clones. (`settings.local.json`
     is already ignored regardless.) If the dirs were already committed in a prior
     history, also run `git rm -r --cached .claude .devcontainer` so the ignore
     takes effect.

   **`.gitattributes`**:
   ```
   * text=auto
   ```

   **`STATUS.md`** — the present tense only (future → `_planning/backlog.md`,
   past → `CHANGELOG.md`):
   ```markdown
   # Project Status

   Last updated: YYYY-MM-DD HH:MM

   ## In Progress
   _None yet_

   ## Blockers
   _None_

   Next: top of `_planning/backlog.md`.
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
   - `backlog.md` — the only queue of future work:
     ```markdown
     # Backlog

     ## High Priority
     - Initial project setup

     ## Medium Priority

     ## Low Priority / Ideas
     ```
   - `plans/` — empty directory (create with a `.gitkeep`)

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
   See `STATUS.md` for current work and `CHANGELOG.md` for completed milestones.
   ```
   If CLAUDE.md already exists, just ensure it has the STATUS.md/CHANGELOG.md reference line.

   Then ask the user which commit policy they want — on request only /
   automatically at milestones / periodically — and record it in CLAUDE.md as
   `Commit policy: on-request | milestones | periodic`.

3. Rename the dev container to this project. If `.devcontainer/devcontainer.json`
   still has `"name": "Claude Boilerplate Repo"` (the boilerplate default),
   replace it with the project name. This is also the signal the first-run
   SessionStart hook uses to detect an un-detached copy, so renaming it stops
   that nudge. (`scripts/new-project.sh` already does this on detach; do it here
   for copies that skipped the script.)

4. Initialize git if not already a repo (`git init`).

5. Report what was created, listing each file. Also point out the **bundled skills**
   in `.claude/skills/` (`test-driven-development`, `systematic-debugging`,
   `using-superpowers`): they need no install — Claude Code auto-discovers them and
   invokes the matching one on its own. Mention they can delete any folder they
   don't want (especially `using-superpowers`, which makes Claude reach for skills
   aggressively), and that the full upstream set is available via the Superpowers
   plugin instead. See `.claude/skills/ATTRIBUTION.md`.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*