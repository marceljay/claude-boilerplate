---
name: log
description: Use when completed work needs a CHANGELOG.md entry — on finishing a feature, fix, or other user-visible change, as part of a milestone commit, or when the user asks to log or release. Completion always pairs with the update-status skill (the item leaves STATUS.md in the same edit).
---

# Add Changelog Entry

Record completed work for the changelog. This skill fires automatically when
work completes — don't wait to be asked; write the entry and show it. If the
completed item is listed in `_planning/STATUS.md`, remove it there in the same
edit (the `update-status` skill) — move, never copy.

**Where the entry goes depends on `.claude/CUSTOM.md`'s `Changelog:` line.**
Default, and the only safe choice with more than one agent, branch, or
worktree, is **`fragments`**: never edit `CHANGELOG.md` on a branch. Write one
file per change instead:

```
changelog.d/<slug>.<added|changed|fixed|removed>.md
```

`<slug>` is a short kebab-case name for the change (branch name is fine).
The file holds the bullet text only — the same markdown you would have put
under `[Unreleased]`, leading `- ` optional. Two branches never touch the same
file, so there is nothing to conflict. `.claude/scripts/changelog_fold.py`
folds pending fragments into `[Unreleased]` on the release branch (the
`release` skill runs it at a cut; run it by hand after merges if you want
CHANGELOG.md current between releases). With `Changelog: inline`, edit
`CHANGELOG.md` directly as in step 3 — single-branch projects only.

## Steps

1. Read the current `CHANGELOG.md`. If it doesn't exist, create one with this format:

```markdown
# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added

- New feature description

### Changed

- Change description

### Fixed

- Bug fix description
```

2. Determine the entry type from the user's input or recent git history:
   - **Added** — new features or capabilities
   - **Changed** — modifications to existing functionality
   - **Fixed** — bug fixes
   - **Removed** — removed features or deprecated items

3. Write the entry: with `Changelog: fragments` (default), create the
   `changelog.d/` file named above (create the directory if missing); with
   `inline`, add it under `[Unreleased]` in the matching category. Either way
   use concise, user-facing language (not implementation details), one bullet
   starting with a bold phrase naming the change.

4. **Versions are the `release` skill's job.** Leave the entry under
   `[Unreleased]` and don't ask about tagging. If the user hints at a release
   (mentions a version, "release", "ship", "tag"), the `release` skill takes
   over: it fetches first, picks the number, moves `[Unreleased]` under a
   `[<version>] - YYYY-MM-DD` heading, bumps the version file, and tags on
   the release branch. Never add to a version section that has shipped.

5. Show what was added.
