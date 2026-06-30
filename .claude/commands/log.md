# Add Changelog Entry

Add an entry to `CHANGELOG.md` documenting completed work.

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

4. **Version tagging:** Only ask about tagging a release when the user hints
   at one (mentions a version, "release", "ship", "tag") — otherwise leave the
   entry under `[Unreleased]` without asking. When they do want a release,
   move all `[Unreleased]` items under a new version heading:

   ```markdown
   ## [1.3.0] - 2026-02-11

   ### Added

   - Feature description

   ### Fixed

   - Bug fix description
   ```

   Then create a fresh empty `[Unreleased]` section above it. Suggest semver bumps:
   - **Patch** (1.0.X) — bug fixes only
   - **Minor** (1.X.0) — new features, backwards compatible
   - **Major** (X.0.0) — breaking changes

5. Show what was added.

---
