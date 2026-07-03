---
name: update-status
description: Use when a work item starts, completes, or becomes blocked, and as part of every milestone commit — moves items between In Progress/Blockers/Backlog in _planning/STATUS.md and CHANGELOG.md so finished work never lingers in STATUS.md. Also for adding or reprioritizing backlog items.
---

# Update Project Status

Update `_planning/STATUS.md` (gitignored, private by default) — the single living
state file. It owns the
**present** (In Progress, Blockers) and the **future** (Backlog, the only queue);
finished work moves out to `CHANGELOG.md`. An item moves between sections/files; it
is never copied.

**This skill fires automatically** at state transitions — when work starts,
finishes, or gets stuck, and at every milestone commit — not just when the user
types `/update-status`. When it fires automatically, don't ask for permission to
do the bookkeeping: make the move, then show what changed in one or two lines.
The whole point is that finished items leave "In Progress" at the moment of
completion, not when someone remembers to clean up.

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

2. Apply the updates for the transition that triggered this skill:
   - **In Progress** holds at most ~3 truly active items. Starting something new
     means pulling it from the top of the `# Backlog` section (below, same file)
     into In Progress and deleting it from the backlog — move, never copy.
   - When an item **completes**: remove it from In Progress and add the
     `CHANGELOG.md` entry (the `log` skill) **in the same edit**. STATUS.md has no
     "Recently Completed" section — the past lives in CHANGELOG.md.
   - **Blockers** is for items stuck on input or external events; name what
     unblocks them.
   - **Backlog** edits (add/reprioritize/remove future work) happen here too.
   - **Always update the "Last updated" date** (YYYY-MM-DD) on any edit — this is
     the signal `/status` uses to detect staleness.
   - While editing, delete any `<!-- context compacted … -->` markers left by the
     PreCompact hook — they've served their purpose once the file is reconciled.

Do NOT put any of this in CLAUDE.md. Keep one home per work item: future and present
live in their own sections of STATUS.md, the past in CHANGELOG.md.
