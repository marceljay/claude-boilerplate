# Update Project Status

Update `STATUS.md` to reflect current project state. The user may provide specific updates, or you may infer from recent work.

## Steps

1. Read the current `STATUS.md`. If it doesn't exist, create one with this template:

```markdown
# Project Status

Last updated: YYYY-MM-DD HH:MM

## In Progress
- [ ] Item description

## Blockers
_None_

## Up Next
- [ ] Item description

## Recently Completed
- [x] Item description (YYYY-MM-DD HH:MM)
```

2. Apply the user's updates:
   - Move completed items from "In Progress" to "Recently Completed" with date and time (YYYY-MM-DD HH:MM)
   - Add new items to the appropriate section
   - Update the "Last updated" timestamp with date and time
   - Keep "Recently Completed" trimmed to the last 10 items. Older ones belong in CHANGELOG.md

Do NOT put any of this information in CLAUDE.md.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*