# Update Project Status

Update `STATUS.md` to reflect what is in flight **right now**. STATUS.md owns
the present only — queued work lives in `_planning/backlog.md`, finished work
in `CHANGELOG.md`. An item moves between these files; it is never copied.

## Steps

1. Read the current `STATUS.md`. If it doesn't exist, create one with this template:

```markdown
# Project Status

Last updated: YYYY-MM-DD HH:MM

## In Progress
_None_

## Blockers
_None_

Next: top of `_planning/backlog.md`.
```

2. Apply the user's updates:
   - "In Progress" holds at most ~3 truly active items. Starting something new
     means pulling it from the top of `_planning/backlog.md` and deleting it
     there — move, never copy.
   - When an item completes: remove it from "In Progress" and add the
     `CHANGELOG.md` entry (the `/log` flow) **in the same edit**. There is no
     "Recently Completed" parking lot.
   - "Blockers" is for items stuck on input or external events; name what
     unblocks them.
   - Update the "Last updated" timestamp (YYYY-MM-DD HH:MM).

Do NOT put any of this in CLAUDE.md, and never add an "Up Next" or "Recently
Completed" section to STATUS.md — the future belongs to backlog.md, the past
to CHANGELOG.md.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*
