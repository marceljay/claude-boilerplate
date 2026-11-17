- **`sync-harness.sh` no longer overwrites local edits in the mirrored
  `.claude/` directories, and no longer asks about a project's own
  files.** Each file in `commands/`, `skills/`, `agents/`, `hooks/` and
  `scripts/` is checked against the boilerplate's git history. A copy
  that matches a past boilerplate version is updated without a prompt; a
  copy that matches none was edited in the project, so the script shows
  the diff and offers overwrite, keep, or keep plus a `.upstream` copy.
  A file only the target has is listed for deletion only when the
  boilerplate once shipped that path, together with the commit that
  removed it; any other target-only file is the project's own and is
  kept. Emptied folders are removed along with retired files. Each
  directory reports `in sync` or a count of new, updated and kept files
  instead of the old `mirrored` line. Without git history (no `.git`, or
  a shallow clone) it falls back to asking about every target-only file.
