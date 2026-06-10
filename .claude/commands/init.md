# Initialize Project Structure

Scaffold the standard file structure for a new project.

## Steps

1. Detect project context:
   - Read `package.json` or other config files to determine project name and description
   - Check what already exists — don't overwrite existing files
   - Determine the tech stack from existing files

2. Create the following files if they don't exist:

   **`.gitignore`** — with at minimum:
   ```
   node_modules/
   .env*
   .vercel/
   .supabase/
   *.pem
   *.key
   .DS_Store
   Thumbs.db
   ```
   Add framework-specific entries based on detected stack (e.g., `.next/` for Next.js, `dist/` for builds).

   **`.gitattributes`**:
   ```
   * text=auto
   ```

   **`STATUS.md`**:
   ```markdown
   # Project Status

   Last updated: YYYY-MM-DD HH:MM

   ## In Progress
   _None yet_

   ## Blockers
   _None_

   ## Up Next
   - [ ] Initial project setup

   ## Recently Completed
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
   - Setup/install instructions (`npm install`, env vars needed)
   - Development commands (`npm run dev`, etc.)
   - Deployment info if detectable

   **`_planning/`** directory with:
   - `backlog.md` — empty template:
     ```markdown
     # Backlog

     ## High Priority

     ## Medium Priority

     ## Low Priority / Ideas
     ```
   - `plans/` — empty directory (create with a `.gitkeep`)

   **`CLAUDE.md`** — if it doesn't exist, create a starter:
   ```markdown
   # Project Name

   Brief description.

   ## Commands
   - Dev: `npm run dev`
   - Build: `npm run build`
   - Lint: `npm run lint`

   ## Architecture
   <!-- Add project structure and key patterns here -->

   ## Current Status
   See `STATUS.md` for current work and `CHANGELOG.md` for completed milestones.
   ```
   If CLAUDE.md already exists, just ensure it has the STATUS.md/CHANGELOG.md reference line.

3. Initialize git if not already a repo (`git init`).

4. Report what was created, listing each file.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*