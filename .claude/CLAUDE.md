# Global Claude Code Instructions

## Preference Persistence

When offering Yes/No options with a "during this session" scope, always include a third option to save the preference globally. For example:

```
1. Yes
2. Yes, always do this (session only)
3. Yes, always do this (save globally)
```

If the user picks option 3:
- **Behavioral preferences** (e.g., "always run tests after changes", "don't ask before committing") -> append to this file (`~/.claude/CLAUDE.md`)
- **Tool permissions** (e.g., "allow rm commands", "allow docker") -> add to `~/.claude/settings.json` under `permissions.allow`

Default to recommending option 3 over option 2. Session-only preferences are lost on context compression and /clear, making them unreliable. Prefer durable persistence.

## Safety Net (bypassPermissions mode is ON)

Since all actions are auto-approved, follow these guardrails:
- **Announce destructive actions** (rm, git reset, drop table, etc.) before executing. Give the user a moment to cancel.
- **Commit atomically.** Make small, focused commits so any change can be cleanly reverted with `git revert`.
- **Never force-push to main/master** without explicit confirmation.
- **Never delete files outside the project directory** without explicit confirmation.
- **Never modify `~/.claude/settings.json` or `~/.claude/CLAUDE.md`** without showing the proposed change first and getting a yes.

## Project State Management

**CLAUDE.md is for stable instructions only.** Never store TODOs, changelogs, sprint status, session context, or completed work in CLAUDE.md. These change frequently and burn context window on every conversation.

Use this consistent file structure across all projects:

```
project/
├── CLAUDE.md           # Stable: commands, conventions, architecture, gotchas
├── STATUS.md           # Active: current TODOs, in-progress work, blockers
├── CHANGELOG.md        # History: versioned release notes, completed milestones
├── _planning/          # Planning (optional, for larger projects)
│   ├── backlog.md      # Prioritized feature backlog
│   ├── sprint.md       # Current sprint scope and progress
│   ├── plans/          # Saved plans from Plan Mode (auto-saved here)
│   │   └── YYYY-MM-DD-plan-name.md
│   └── research/       # Research docs, vendor analysis, etc.
```

Rules:
- If content changes more than once a month, it does NOT belong in CLAUDE.md
- CLAUDE.md should reference state files (e.g., "See STATUS.md for current work")
- When starting a session, read both CLAUDE.md and STATUS.md for full context
- When wrapping up significant work, update STATUS.md and CHANGELOG.md, not CLAUDE.md

### Plan Mode Persistence

When exiting Plan Mode, always save the plan to `_planning/plans/YYYY-MM-DD-descriptive-name.md`. Each plan file must include:
- A title and date
- The objective/goal
- Implementation steps with checkboxes (`- [ ]` / `- [x]`)
- Update checkboxes as steps are completed during implementation

Slash commands for managing project state: `/status`, `/update-status`, `/log`, `/backlog`, `/plans`

## Context Preservation (Auto-Save Before Compaction)

A `PreCompact` hook is configured in settings.json that fires before auto-compaction. When you see `CONTEXT_SAVE_TRIGGERED` or sense the conversation is very long, immediately save all session state:

1. **STATUS.md** — Update with current in-progress work, blockers, and what was just completed
2. **Plan files** — If a plan is active, save/update it in `_planning/plans/` with current checkbox states
3. **Memory** — Write any new learnings, patterns, or gotchas discovered this session to the project's `memory/MEMORY.md`
4. **CHANGELOG.md** — Log any completed features or fixes not yet recorded

After saving, inform the user: "Context is getting large. I've saved current state to STATUS.md, plans, and memory. Safe to /clear or continue."

Do NOT wait for the user to ask. Do this automatically.

## Token Optimization

- Read files with targeted line ranges (`offset`/`limit`) when possible, not entire files.
- Delegate broad codebase exploration to subagents to protect main context.
- Don't re-read files immediately after editing them.
- When showing results, summarize rather than dumping raw output.
- Prefer pasting error text over screenshots when communicating issues.

## Communication Style

- Be concise. Don't explain what you're about to do, just do it. Skip preamble.
- Don't narrate your thought process or list what you're about to do. Just show results and summarize what changed.

## Git Conventions

- Use conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`. Keep messages under 72 chars.
- Don't commit unless asked.
- When creating branches, use format: `feat/description`, `fix/description`, `chore/description`.

## Error Recovery

When a command or approach fails, try to fix it once. If the second attempt fails, pause and explain:
- What was attempted
- What remains unknown
- Ask if the user can provide input to assist troubleshooting, such as error logs, browser console messages, screenshots, or other context.

Do NOT loop on the same failing approach.

## Code Quality

- After editing code files, run the project's linter if one exists. Fix lint errors automatically without asking.
- Run existing tests after code changes. Don't write new tests unless asked.
- When creating new components, co-locate related files (component, hook, types) rather than separating by type.
- **Treat build warnings as errors.** Never dismiss, rationalize, or skip over warnings in build output, linter output, or compiler output. Every warning must be investigated and resolved. Do not say "this warning is safe to ignore." Fix it. If a warning truly cannot be resolved, explain why specifically and ask the user to confirm it's acceptable.

## Security

- **Never commit secrets.** Before any git commit, verify that `.env`, `.env.local`, `.env.production`, `credentials.json`, API keys, and similar files are in `.gitignore`. If they aren't, add them before committing and warn the user.
- **Check .gitignore on project init.** When creating a new project or adding environment variables for the first time, ensure `.gitignore` exists and covers: `.env*`, `*.pem`, `*.key`, `node_modules/`, `.vercel/`, `.supabase/`.
- **Create .gitattributes on project init.** When initializing a new project or repo, create a `.gitattributes` file with `* text=auto` to normalize line endings across platforms.
- **Flag exposed secrets.** If you encounter hardcoded API keys, tokens, passwords, or connection strings in source code, flag them immediately and move them to environment variables.
- **No secrets in CLAUDE.md or memory files.** Never write API keys, passwords, or tokens to any CLAUDE.md or memory file.
