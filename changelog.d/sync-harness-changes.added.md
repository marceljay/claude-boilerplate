- **`sync-harness.sh` shows what changed since the last sync, and stops
  a downgrade.** Before syncing, it reads the commit recorded in the
  target's `.claude/HARNESS_VERSION` and lists the boilerplate commits
  since then that touched the synced paths, each with its title and
  summary paragraph (newest 25). `--install-shell` does the same for
  `agent-sandbox.zsh`, finding the installed copy's commit by content (or
  by its version line when it was edited). When the boilerplate checkout
  is older than the target's harness or on another branch, it lists the
  commits the sync would remove and asks before going on (default No);
  an installed `agent-sandbox.zsh` newer than the one offered gets a
  DOWNGRADE warning.
