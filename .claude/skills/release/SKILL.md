---
name: release
description: Use for anything touching a version number — cutting a release, bumping the version file, tagging, editing a CHANGELOG version heading, dependency upgrades, or merging a dev branch into main. Fires before any of those, not only when asked; always establishes what has shipped from the remote first.
---

# Releases, versions and upgrades

The `log` skill writes CHANGELOG entries; `update-status` moves work between
STATUS.md and CHANGELOG.md. This one owns the **version**: what number, what
belongs under it, when it is frozen, and what must be true before it moves.
Handle all of it without being asked; ask only where §6 says to.

## 1. Establish reality first — every time

Local refs go stale: other sessions push, PRs merge. Reasoning off a stale ref
is how already-published commits get rewritten and shipped CHANGELOG sections
get edited. One command prevents it:

```sh
git fetch origin --tags
```

Then answer these before deciding anything, never from memory. `<main>` is the
release branch (usually `main`); `<dev>` is the integration branch if the repo
has one, else skip those lines:

```sh
git rev-parse --short origin/<main> origin/<dev>     # where the lines actually are
git log --oneline origin/<main>..origin/<dev>        # what is unreleased
git ls-remote --tags origin | grep -v '\^{}'         # which versions exist as refs
git merge-base --is-ancestor <commit> origin/<main>  # has this shipped?
```

**A version is released if its release commit is reachable from
`origin/<main>`, or a tag for it exists on the remote — either one.** Not "if I
remember cutting it", not "if `main` looks behind".

## 2. A released version is frozen

Its CHANGELOG section is a historical record. Never add entries to it, never
re-date or re-scope it. Later work goes under `[Unreleased]` and then into the
*next* version. A released section that is wrong gets fixed forward under a
new version, and you say so.

## 3. Cutting a release

In one commit, in this order:

1. Confirm §1. Run `python3 .claude/scripts/changelog_fold.py --check`: if
   it lists no fragments and `[Unreleased]` is empty, there is nothing to cut
   — stop.
2. Pick the number (§4).
3. Bump the version where the stack keeps it, and every copy of it:
   `package.json` **and both** `version` fields in `package-lock.json` (root
   and `packages[""]`); `Cargo.toml` and `Cargo.lock`; `pyproject.toml`;
   `go.mod` has none — Go versions live in the tag only. Verify by reading the
   files back, not by trusting the edit.
4. `python3 .claude/scripts/changelog_fold.py --version <version>`: folds
   pending `changelog.d/` fragments plus whatever is under `[Unreleased]` into
   `## [<version>] - YYYY-MM-DD` and leaves a fresh empty `[Unreleased]`
   above it. Read the result; it is the release notes.
5. Run lint, build, and the full test suite. All three; report the numbers.
6. Commit as `chore(release): <version>` (body per CLAUDE.md commit rules).

Then, once it is on `<main>`:

7. **Tag on `<main>`, never on the dev branch**, at the release/merge commit:
   `git tag -a v<version> <sha> -m "<version>"` then
   `git push origin v<version>`.
8. Verify with `git ls-remote --tags origin`. A tag not on the remote does not
   exist.

## 4. Choosing the number

Semver, weighted by what a user would notice:

- **Patch** — fixes, dependency work, refactors, docs.
- **Minor** — a feature a user would name.
- **Major** — a break in what users or operators rely on. Pre-1.0 projects
  may use minor for this; say so in the CHANGELOG heading's first line.
- Numbers may skip; never reuse or rewind one.

**Say what the digit understates.** A patch that changes the base image, adds a
migration, or needs an operator to act gets that written in the CHANGELOG entry
and the commit body. The number says "safe to skim"; if that's untrue, the text
must say so.

## 5. Dependency upgrades

Principle: **the version that fixes it, not the latest.**

- Read `engines` / `rust-version` / `requires-python` and peer requirements
  **before** installing. Compare against the Dockerfile, the devcontainer, and
  any deploy image. A major that drops the runtime production runs on is a
  decision (§6), not a bump.
- Check what an advisory actually requires. `npm audit fix --force` proposes
  `latest` and has proposed *downgrades* to get there.
- Under `ignore-scripts` (this harness's `.npmrc` default), every install
  breaks native bindings — see `.devcontainer/STACKS.md` §Supply-chain
  hardening, "Native modules", for the rebuild step.
- Never run a scratch install inside the repo tree; package managers walk up
  and install into the project. Use `mktemp -d`.
- **All tests passing is not evidence that a major upgrade is safe.** Ask what the suite cannot
  see, and go look: user-visible strings a library generates (validation
  messages), escaping it used to do for you (a markdown renderer that stops
  escaping link titles is a stored XSS), code paths no test enters (a static
  file server disabled in the harness), and data written by the *old*
  version (pin a literal hash generated before the upgrade). For a native or
  storage dependency, boot the app for real against a fresh store *and* a
  copy of a populated one.
- One dependency per commit, with what was checked in the body.

## 6. When to ask

Only here, briefly:

- The number, when a release plausibly reads as either patch or minor.
- A major that drops a supported runtime or changes what hosting requires.
- Anything needing a force-push to a shared branch, or moving an existing tag.
- Two different versions of the same released number found in the wild —
  report both, let the user choose which is true.

Everything else: decide, do it, report what you decided.

## 7. Never

- Never edit or re-date a released CHANGELOG section (§2).
- Never tag from a dev branch, or tag a commit not reachable from `origin/<main>`.
- Never bump a version without lint, build, and the suite.
- Never force-push `<main>`.
- Never conclude what has shipped without a fresh `git fetch`.
