- **Changelog entries are per-change fragments, not edits to `CHANGELOG.md`.**
  Several agents on separate branches or worktrees all inserted at the top
  of `[Unreleased]` and conflicted at the same spot on every merge. Now the
  `log` skill writes `changelog.d/<slug>.<type>.md` on the branch;
  `.claude/scripts/changelog_fold.py` folds fragments into `[Unreleased]`
  (or into the new version section at a `release` cut) on the release
  branch only; `/pr` checks the branch carries its fragment; `/status`
  counts pending fragments as recently completed. `Changelog: fragments |
  inline` in CUSTOM.md records the choice (`/init` asks; fragments is the
  default). This entry is the first fragment.
