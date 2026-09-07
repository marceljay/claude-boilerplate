---
name: log
description: Use when completed work needs a CHANGELOG.md entry — on finishing a feature, fix, or other user-visible change, as part of a milestone commit, or when the user asks to log or release. Completion always pairs with the update-status skill (the item leaves STATUS.md in the same edit).
---

# Add Changelog Entry

Add an entry to `CHANGELOG.md` documenting completed work. This skill fires
automatically when work completes — don't wait to be asked; add the entry and
show it. If the completed item is listed in `_planning/STATUS.md`, remove it
there in the same edit (the `update-status` skill) — move, never copy.

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

3. Add the entry under `[Unreleased]` in the appropriate category. Use concise, user-facing language (not implementation details).

4. **Versions are the `release` skill's job.** Leave the entry under
   `[Unreleased]` and don't ask about tagging. If the user hints at a release
   (mentions a version, "release", "ship", "tag"), the `release` skill takes
   over: it fetches first, picks the number, moves `[Unreleased]` under a
   `[<version>] - YYYY-MM-DD` heading, bumps the version file, and tags on
   the release branch. Never add to a version section that has shipped.

5. Show what was added.
