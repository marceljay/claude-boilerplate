- **Harness version in the status line.** `sync-harness.sh` and
  `new-project.sh` write the boilerplate's `git describe` output (for
  example `v0.3.0-alpha-95-gab33011`) to the project's
  `.claude/HARNESS_VERSION`, and the status line shows it shortened to
  `harness v0.3.0-alpha+95`. A sync prints the old and the new version.
  A `-dirty` suffix marks a sync from a boilerplate with uncommitted
  changes. The boilerplate's own repo computes the version live.
- **`sync-harness.sh` reports only what changed.** Files and directories
  that already match are counted in one `in sync` line instead of one
  line each, and plain harness files (`.claude/README.md`, `STACKS.md`,
  `init-firewall.sh` and others) are copied only when they differ. Every
  file a sync copies or updates is named on its own line, including
  `.claude/HARNESS_VERSION`, instead of a per-directory count. The rebuild hint appears only when the target's
  `.devcontainer/` changed, and an unchanged harness version prints as
  `(unchanged)`.
