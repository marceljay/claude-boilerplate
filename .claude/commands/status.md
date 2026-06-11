# Review Project Status

Read the current project state and summarize it concisely.

1. Read `STATUS.md` in the project root. If it doesn't exist, say so and offer
   to create one (see `/update-status` for the template).
2. Read the top of `_planning/backlog.md` for what's queued next.
3. Optionally scan recent git log (last 5 commits) and the top of
   CHANGELOG.md `[Unreleased]` for completions context.
4. Present a summary:
   - **In Progress** — active items (from STATUS.md)
   - **Blockers** — anything stuck or waiting on input (from STATUS.md)
   - **Up Next** — top backlog items, in priority order (from backlog.md)
   - **Recently Completed** — from CHANGELOG.md `[Unreleased]` / git log

Keep the summary short and actionable. Don't read CLAUDE.md for status —
that's not where it lives. Note: STATUS.md deliberately has no Up Next or
Recently Completed sections; those live in backlog.md and CHANGELOG.md.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*
