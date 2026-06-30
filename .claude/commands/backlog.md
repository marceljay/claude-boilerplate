# Review Backlog

Review and manage upcoming work. The backlog lives in the **`# Backlog` section of
`_planning/STATUS.md`** (gitignored, private by default) — it is the only queue of
future work. There is no separate `backlog.md`; keeping the queue in the same file
as "In Progress" is deliberate, so you can't look at what's next without also seeing
(and fixing) what's stale.

## Steps

1. Read `_planning/STATUS.md`, focusing on its `# Backlog` section. If it doesn't
   exist, offer to create it (see `/update-status` for the template). If it exists
   but has no `# Backlog` section, add one with
   `## High Priority` / `## Medium Priority` / `## Low Priority / Ideas`
   subsections. For seed material, check GitHub Issues (`gh issue list --limit 20`)
   and offer to populate from what you find or from the user's input.

2. Present the backlog organized by priority:
   - **High Priority** — should be done soon; the top item is "next up"
   - **Medium Priority** — planned but not urgent
   - **Low Priority / Ideas** — nice to have, or open questions

3. While you're here, glance at `## In Progress` above the backlog. If it looks
   stale (items that are clearly done, or the "Last updated" date is old), say so —
   this is the moment to reconcile it.

4. If the user asks to reprioritize, edit the `# Backlog` section in place. When
   work **starts** on an item, move it up to `## In Progress` and delete it from
   the backlog — move, never copy. Bump the "Last updated" date on any edit.

---

_By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)_
