# Initialize Project Structure

Scaffold the standard file structure for a new project.

## Steps

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

3. Initialize git if not already a repo (`git init`).

4. Report what was created, listing each file.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*