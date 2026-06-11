# The `.claude/` Directory — What Everything Here Does

This folder configures how Claude Code behaves in this project. Nothing here is
application code; it's all instructions and configuration for the AI harness.
This README explains each piece in plain terms so you can edit it confidently.

> **TL;DR of the moving parts**
> | Thing | File(s) | Loaded when | Who runs it |
> |-------|---------|-------------|-------------|
> | Project instructions | `CLAUDE.md` | **Every** message | Claude reads it |
> | Permissions & hooks | `settings.json` | Session start | The harness |
> | Slash commands | `commands/*.md` | When you type `/name` | Claude reads it |
> | Subagents | `agents/*.md` | When delegated to | A separate Claude |
> | Memory | `memory/*.md` | Recalled on relevance | Claude reads it |

## Contents

- [1. `CLAUDE.md` — always-on instructions](#1-claudemd--always-on-instructions)
- [2. `settings.json` — permissions and hooks](#2-settingsjson--permissions-and-hooks)
  - [`permissions`](#permissions)
  - [`hooks` — the part you asked about](#hooks--the-part-you-asked-about)
- [3. `commands/` — slash commands](#3-commands--slash-commands)
- [4. `agents/` — subagents (the biggest usage-saver)](#4-agents--subagents-the-biggest-usage-saver)
- [5. `memory/` — persistent facts across sessions](#5-memory--persistent-facts-across-sessions)
- [6. How the project-state files relate (set by `CLAUDE.md`)](#6-how-the-project-state-files-relate-set-by-claudemd)
- [7. `.devcontainer/` (sibling folder, not under `.claude/`)](#7-devcontainer-sibling-folder-not-under-claude)
- [Editing cheatsheet](#editing-cheatsheet)

---

## 1. `CLAUDE.md` — always-on instructions

This is the most important file and the one to be most careful with. **Its
entire contents are injected into the context window on every single message.**
That means:

- It's powerful: rules here are always in effect.
- It's expensive: every word costs tokens on every turn. A 500-line CLAUDE.md is
  paid for thousands of times over a project's life.

**Rule of thumb:** only put *stable, always-relevant* instructions here. Anything
needed occasionally (e.g. "how to do a release") belongs in a **slash command**
(section 3), which only loads when invoked. This directly serves the
"reduce usage" goal — a lean CLAUDE.md is cheaper on every interaction.

---

## 2. `settings.json` — permissions and hooks

This is read by the **harness** (the program running Claude), not by Claude
itself. Two main sections:

### `permissions`

Controls which tool calls run without asking you. Patterns match the command
Claude wants to run.

```jsonc
"allow": [ "Bash(npm:*)", "Bash(git status:*)" ],  // run silently
"deny":  [ "Bash(rm -rf:*)", "Bash(git push --force:*)" ]  // always blocked
```

- `allow` — auto-approved, no prompt. Good for safe, frequent commands.
- `deny` — hard-blocked, even if Claude tries. Your safety net.
- Anything not listed → Claude asks you for permission interactively.

`Bash(npm:*)` means "any command starting with `npm`". The `:*` is a wildcard.

### `hooks` — the part you asked about

A **hook** is a shell command **the harness runs automatically** when a specific
event happens during a session. Claude does *not* decide to run a hook — the
harness fires it on your behalf, every time, deterministically. That's the key
difference from instructions: instructions are suggestions Claude *may* follow;
hooks are guarantees the harness *will* execute.

The shape of a hook entry:

```jsonc
"hooks": {
  "PreCompact": [                       // <- the event name
    {
      "matcher": "auto",                // <- which variant of the event
      "hooks": [
        { "type": "command",
          "command": "echo CONTEXT_SAVE_TRIGGERED" }  // <- what runs
      ]
    }
  ]
}
```

Common events you can hook:

| Event | Fires when… | Typical use |
|-------|-------------|-------------|
| `PreCompact` | Just before context is auto-summarized | Save state so nothing is lost |
| `PreToolUse` | Before Claude runs any tool | Block/validate a command, log it |
| `PostToolUse` | After a tool finishes | Auto-format edited files, run linter |
| `UserPromptSubmit` | You send a message | Inject extra context |
| `Stop` | Claude finishes responding | Notify you, run tests |
| `SessionStart` | A session begins | Print project status |

**Why hooks matter for this project:** the current `PreCompact` hook only does
`echo CONTEXT_SAVE_TRIGGERED`. That echo doesn't save anything — it just prints
a string that Claude is told to watch for and then *manually* react to. A real
hook would run a script that writes `STATUS.md` itself, so the save happens even
if Claude misses the cue. Hooks are how you turn "Claude usually remembers to X"
into "X always happens."

A practical example you might add — auto-format every file Claude edits:

```jsonc
"PostToolUse": [
  { "matcher": "Edit|Write",
    "hooks": [ { "type": "command",
      "command": "npx prettier --write \"$CLAUDE_FILE_PATHS\" 2>/dev/null || true" } ] }
]
```

---

## 3. `commands/` — slash commands

Each `.md` file here becomes a `/command`. When you type `/cleanup`, the harness
loads `commands/cleanup.md` and feeds it to Claude as instructions **for that one
turn**. When you don't use it, it costs nothing.

Think of commands as "scripts written in English." They're the right home for
any procedure that's needed *sometimes* — releases, PR creation, status updates —
keeping it out of the always-loaded `CLAUDE.md`.

This project ships: `init`, `cleanup`, `status`, `update-status`, `log`,
`backlog`, `plans`, `pr`, `deploy`, `dev`, `docs`, `remember`. Open any of them —
they're just markdown with a numbered list of steps.

To add one: create `commands/foo.md`, write the instructions, and it's available
as `/foo`. No restart needed.

---

## 4. `agents/` — subagents (the biggest usage-saver)

A **subagent** is a *separate* Claude instance that the main Claude can hand a
task to. It runs with its own fresh context window, does the work, and returns
only a short summary to the main conversation.

Why this saves usage: imagine you ask "find everywhere we call the payments API."
Without a subagent, the main Claude reads 30 files into *your* context window —
all those tokens now ride along on every later message. With a subagent, that
reading happens in a throwaway context, and only the 5-line answer comes back.
Your main context stays small and cheap.

A subagent is defined by a markdown file with frontmatter:

```markdown
---
name: explore
description: Read-only codebase search. Use for "where is X" / "how does Y work"
              questions that require reading many files.
tools: Read, Grep, Glob       # optional — restrict what it can do
---

You are a code exploration agent. Search thoroughly, read only what's needed,
and return a concise answer with file:line references. Do not modify files.
```

Save that as `agents/explore.md` and the main Claude can delegate to it. Good
default agents for almost any project:

- **explore / search** — read-only fan-out searches (keeps main context lean).
- **reviewer** — reviews a diff for bugs; returns a findings list.

> This boilerplate doesn't ship any agents yet — adding an `explore` agent is the
> single highest-impact change for the "reduce usage" goal.

---

## 5. `memory/` — persistent facts across sessions

A place for Claude to write durable notes (one fact per file) that survive
`/clear` and compaction. An index file (`MEMORY.md`) lists them so Claude knows
what's available. Use it for project facts that aren't obvious from the code —
decisions, constraints, "why we did it this way." Not for TODOs (those go in
`STATUS.md`) and never for secrets.

---

## 6. How the project-state files relate (set by `CLAUDE.md`)

This boilerplate's `CLAUDE.md` defines a convention worth knowing:

- **`CLAUDE.md`** — stable only (commands, architecture). Changes rarely.
- **`STATUS.md`** — live TODOs, current work, blockers. Changes constantly.
- **`CHANGELOG.md`** — history of completed/released work.
- **`_planning/`** — backlog and saved plans.

The point: keep fast-changing stuff *out* of `CLAUDE.md` so you're not paying to
load this week's TODO list on every message.

---

## 7. `.devcontainer/` (sibling folder, not under `.claude/`)

Defines the sandboxed Docker environment Claude runs in: the image
(`Dockerfile`), a network firewall (`init-firewall.sh`), and editor/mount config
(`devcontainer.json`). You generally only touch this when changing the runtime
environment, not day-to-day.

---

## Editing cheatsheet

| I want to… | Edit… |
|------------|-------|
| Add an always-on rule | `CLAUDE.md` (sparingly!) |
| Auto-approve a safe command | `settings.json` → `permissions.allow` |
| Make something happen automatically on an event | `settings.json` → `hooks` |
| Add a reusable `/procedure` | new file in `commands/` |
| Offload heavy reading to save context | new file in `agents/` |
| Record a durable project fact | `memory/` + index in `MEMORY.md` |
