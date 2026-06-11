# Boilerplate updates: state-file tenses + memory failsafe

Handoff for a Claude session working in the boilerplate repo
([ds1/boilerplate.md](https://github.com/ds1/boilerplate.md) or its fork).
Both changes below were designed and field-tested in the shark-attack-atlas
project on 2026-06-11. Apply them to the boilerplate's command files and
global CLAUDE.md template.

---

## Part 1 — Remove STATUS.md / backlog.md / CHANGELOG.md overlap

### Problem (observed in practice)

The boilerplate keeps **two queues** (STATUS.md "Up Next" and
`_planning/backlog.md`) and **two completion records** (STATUS.md "Recently
Completed" and CHANGELOG.md), with no rule for which file owns what:

- Work items land wherever the writer happened to be. In a real session, two
  high-priority bugs lived only in backlog.md while features lived only in
  STATUS "Up Next" — a session following the documented ritual ("read
  STATUS.md at session start") answered "what's left to do?" while blind to
  half the queue.
- `/backlog`'s fallback chain even lists STATUS.md "Up Next" as a backlog
  source — admitting they're the same concept.
- "Recently Completed → trim to 10 → migrate older to CHANGELOG" duplicates
  done-work in two files with different phrasing until a manual migration.

### Fix: one file per tense, items move (never copy)

| File | Owns | Session start |
|---|---|---|
| `STATUS.md` | **Now** — ≤3 In Progress items + Blockers, nothing else | read fully |
| `_planning/backlog.md` | **Future** — the only queue, priority-ordered; top = next up | skim |
| `CHANGELOG.md` | **Past** — the only completion record | no |

Lifecycle: backlog → STATUS "In Progress" → CHANGELOG. Each transition
deletes the item from the previous file.

### Concrete edits

1. **`commands/init.md` and `commands/update-status.md` — new STATUS template** (drop "Up Next"
   and "Recently Completed"):

   ```markdown
   # Project Status

   Last updated: YYYY-MM-DD HH:MM

   ## In Progress
   _None_

   ## Blockers
   _None_

   Next: top of `_planning/backlog.md`.
   ```

2. **`commands/update-status.md` — replace the update rules with:**
   - "In Progress" holds at most ~3 truly active items. Starting something new
     means pulling it from the top of `_planning/backlog.md` and deleting it
     there — move, never copy.
   - When an item completes: remove it from "In Progress" and add the
     CHANGELOG.md entry (the `/log` flow) in the same edit. No "Recently
     Completed" parking lot.
   - "Blockers" is for items stuck on input/external events; name what
     unblocks them.
   - Never add "Up Next" or "Recently Completed" sections to STATUS.md.

3. **`commands/backlog.md`** — remove STATUS.md from the fallback chain
   (keep `_planning/sprint.md` and GitHub Issues as *material* for creating
   backlog.md, never as live queues). State explicitly: backlog.md is the
   only queue; when work starts, the item moves to STATUS.md "In Progress".

4. **`commands/status.md`** — the summary now reads three sources:
   In Progress + Blockers from STATUS.md; Up Next from the top of backlog.md;
   Recently Completed from CHANGELOG.md `[Unreleased]` / `git log -5`.

5. **`commands/init.md`** — seed backlog.md's High Priority with the
   "Initial project setup" item that used to go in STATUS "Up Next".

6. **Global CLAUDE.md template, "Project State" section** — replace the
   file-roles + session-start lines with:

   ```
   State files own one tense each, and an item moves between them (never
   copied): `STATUS.md` = now (≤3 in-progress items + blockers),
   `_planning/backlog.md` = future (the only queue, priority-ordered),
   `CHANGELOG.md` = past (the only completion record).
   Read STATUS.md and skim `_planning/backlog.md` alongside CLAUDE.md at
   session start.
   ```

7. **`commands/log.md`** (minor) — "Always ask the user if this should be
   tagged as a release" becomes: only ask when the user hints at a release
   (mentions a version, "release", "ship", "tag"); otherwise file under
   `[Unreleased]` silently. For app-style projects the unconditional question
   is a recurring no.

---

## Part 2 — Memory failsafe against devcontainer volume loss

### Problem

In devcontainer setups, `~/.claude` (`CLAUDE_CONFIG_DIR`) is a named Docker
volume (`claude-code-config-${devcontainerId}`). It survives container
restarts and rebuilds, but **everything in it — auto-memory, session
transcripts (what `claude --continue`/`--resume` restore), global prefs — is
lost** on `docker volume prune`, a Docker Desktop reset, or a `devcontainerId`
change (reworked devcontainer config / moved project folder). The workspace
bind mount (the repo) is the only storage that's on the host disk.

### Fix: a `/backup-memory` command + lazy-read pointer

Three pieces:

1. **New command file `commands/backup-memory.md`:**

   ```markdown
   # Backup Memory to Repo

   Mirror the auto-memory directory into the repo so it survives Docker volume
   loss (`docker volume prune`, Docker Desktop reset, devcontainerId change).

   ## Usage
   `/backup-memory` — copy memory → repo
   `/backup-memory restore` — copy repo → memory (after a volume wipe)

   ## Steps

   1. **Backup (default):**
      ```sh
      rm -rf <repo>/_planning/memory-backup
      cp -r "$CLAUDE_CONFIG_DIR/projects/<project-slug>/memory" <repo>/_planning/memory-backup
      ```
      (<project-slug> is the project path with `/` → `-`, e.g. `/workspace`
      → `-workspace`; list `$CLAUDE_CONFIG_DIR/projects/` to find it.)
      Also mirror raw session transcripts (gitignored — may contain secrets
      from tool output; host-disk durability only, never commit):
      ```sh
      mkdir -p <repo>/_planning/transcripts-backup
      cp "$CLAUDE_CONFIG_DIR/projects/<project-slug>/"*.jsonl <repo>/_planning/transcripts-backup/
      ```
      Then commit the memory snapshot (`chore: backup memory snapshot`).

   2. **Restore (if arg is "restore"):**
      ```sh
      cp -rn <repo>/_planning/memory-backup/. "$CLAUDE_CONFIG_DIR/projects/<project-slug>/memory/"
      ```
      `-n` keeps any newer live memories; report which files were restored.
      Restoring transcripts (re-enables `--resume` for old sessions) is the
      same copy in reverse.

   3. Confirm with a one-line summary (file count, destination).

   ## Notes
   - The backup is a cold archive. Do NOT load it into context during normal
     work — the live memory index covers that. Read it only on explicit
     request or after detecting an empty/fresh memory directory.
   ```

2. **`.gitignore` template addition** (in `commands/init.md`):

   ```
   # Raw session transcripts — host-disk backup only, may contain tool output/secrets
   _planning/transcripts-backup/
   ```

   Rationale: the curated memory snapshot is clean and gets committed; raw
   transcripts capture every tool output that ever scrolled by (env vars,
   tokens) and must never enter git history. A gitignored folder inside the
   bind-mounted repo still lives on the host disk, which is the durability
   that matters.

3. **Global CLAUDE.md template — add to the "Project State" section:**

   ```
   A cold memory snapshot lives at `_planning/memory-backup/` (`/backup-memory`
   refreshes it). Don't read it in normal work — only when memory seems missing
   or you need detail the live index lacks; `/backup-memory restore` after a
   volume wipe.
   ```

   The lazy-read rule is the token-cost control: only these three lines load
   every session; snapshot and transcripts are read on demand.

### Verification checklist (run in a devcontainer project)

- [ ] `/backup-memory` produces `_planning/memory-backup/` (committed) and
      `_planning/transcripts-backup/*.jsonl` (ignored — check `git status`)
- [ ] `git check-ignore _planning/transcripts-backup/` succeeds
- [ ] Delete one live memory file, run `/backup-memory restore`, confirm it
      returns and that a *newer* live file is not overwritten
- [ ] New session: confirm the snapshot is not read during unrelated work
