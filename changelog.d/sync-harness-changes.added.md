- **`sync-harness.sh` shows what changed since the project's last sync.**
  Before syncing, it reads the commit recorded in the target's
  `.claude/HARNESS_VERSION` and lists the boilerplate commits since then
  that touched the synced paths, each with its title and summary paragraph
  (newest 25). An unknown commit is reported instead of guessed at.
