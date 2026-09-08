# Project customizations

Per-project choices and deviations the synced `.claude/CLAUDE.md` defers to.
`sync-harness.sh` never touches this file; `/init` fills it in. Where a line
here contradicts `.claude/CLAUDE.md`, this file wins.

## Harness settings

- Harness: committed
- STATUS.md: private
- Commit policy: milestones
- Testing policy: on-request
- Commit session links: off
- Review page: off

## Deviations

- This is the boilerplate's own working copy: the harness is the product,
  and `.boilerplate-dev` at the root keeps detach nudges off.
