# Backup Memory to Repo

Mirror the auto-memory directory into the repo so it survives Docker volume
loss (`docker volume prune`, Docker Desktop reset, devcontainerId change).
The workspace bind mount is the only storage on the host disk — everything
under `$CLAUDE_CONFIG_DIR` lives in a named volume that can vanish.

## Usage

- `/backup-memory` — copy memory → repo
- `/backup-memory restore` — copy repo → memory (after a volume wipe)

## Steps

1. **Backup (default):**

   ```sh
   rm -rf <repo>/_planning/memory-backup
   cp -r "$CLAUDE_CONFIG_DIR/projects/<project-slug>/memory" <repo>/_planning/memory-backup
   ```

   `<project-slug>` is the project path with `/` → `-`, e.g. `/workspace` →
   `-workspace`; list `$CLAUDE_CONFIG_DIR/projects/` to find it.
   `memory-backup/` **is** committed — that's the point, it's the only copy
   outside the container volume — so it must never hold secrets (CLAUDE.md
   §Security). Transcripts (next step) are not.

   Also mirror raw session transcripts (gitignored — may contain secrets from
   tool output; host-disk durability only, never commit):

   ```sh
   mkdir -p <repo>/_planning/transcripts-backup
   cp "$CLAUDE_CONFIG_DIR/projects/<project-slug>/"*.jsonl <repo>/_planning/transcripts-backup/
   ```

   Verify `_planning/transcripts-backup/` is gitignored
   (`git check-ignore _planning/transcripts-backup/`); add the entry if not.
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
  work — the live memory index covers that. Read it only on explicit request
  or after detecting an empty/fresh memory directory.

---
