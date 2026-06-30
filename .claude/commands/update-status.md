# Update Project Status

Update `_planning/STATUS.md` (gitignored, private by default) — the single living
state file. It owns the
**present** (In Progress, Blockers) and the **future** (Backlog, the only queue);
finished work moves out to `CHANGELOG.md`. An item moves between sections/files; it
is never copied.

## Steps

1. Read the current `_planning/STATUS.md`. If it doesn't exist, create it at
   `_planning/STATUS.md` with this template:

```markdown
# Project Status

Last updated: YYYY-MM-DD

## In Progress

_None_

## Blockers

_None_

---

# Backlog

_The only queue of future work, priority-ordered. Top High-Priority item = next up._

## High Priority

## Medium Priority

## Low Priority / Ideas
```

2. Apply the user's updates:
   - **In Progress** holds at most ~3 truly active items. Starting something new
     means pulling it from the top of the `# Backlog` section (below, same file)
     into In Progress and deleting it from the backlog — move, never copy.
   - When an item **completes**: remove it from In Progress and add the
     `CHANGELOG.md` entry (the `/log` flow) **in the same edit**. STATUS.md has no
     "Recently Completed" section — the past lives in CHANGELOG.md.
   - **Blockers** is for items stuck on input or external events; name what
     unblocks them.
   - **Backlog** edits (add/reprioritize/remove future work) happen here too.
   - **Always update the "Last updated" date** (YYYY-MM-DD) on any edit — this is
     the signal `/status` uses to detect staleness.

Do NOT put any of this in CLAUDE.md. Keep one home per work item: future and present
live in their own sections of STATUS.md, the past in CHANGELOG.md.

---
