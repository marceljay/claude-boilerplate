# Review Project Status

Read the current project state and summarize it concisely.

1. Read `_planning/STATUS.md` (gitignored, private by default; if absent, fall back
   to a repo-root `STATUS.md` for projects that made it public). If neither exists,
   say so and offer to create one (see `/update-status` for the template). It holds
   **In Progress**,
   **Blockers**, and the **Backlog** (the queue) — everything live in one file.
2. **Staleness check:** look at the "Last updated" date. If it's more than ~7 days
   old, or if "In Progress" items look already-finished given recent commits, flag
   it: "STATUS.md may be stale (last updated <date>) — want me to reconcile it?"
   Use `git log -5 --oneline` and the top of `CHANGELOG.md` `[Unreleased]` to judge.
3. Present a short summary:
   - **In Progress** — active items
   - **Blockers** — anything stuck or waiting on input; name what unblocks it
   - **Up Next** — the top of the `# Backlog` section, in priority order
   - **Recently Completed** — from `CHANGELOG.md` `[Unreleased]` / recent git log

Keep it short and actionable. Don't read CLAUDE.md for status — that's not where it
lives. "Up Next" comes from STATUS.md's own Backlog section; "Recently Completed"
comes from CHANGELOG.md. STATUS.md itself never has a "Recently Completed" section —
the past belongs to CHANGELOG.md.

---
