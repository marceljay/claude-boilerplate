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
> | Memory | `$CLAUDE_CONFIG_DIR/projects/<repo>/memory/*.md` | Recalled on relevance | Claude reads it |

## Contents

- [1. `CLAUDE.md` — always-on instructions](#1-claudemd--always-on-instructions)
- [2. `settings.json` — permissions and hooks](#2-settingsjson--permissions-and-hooks)
  - [`permissions`](#permissions)
  - [`hooks` — the part you asked about](#hooks--the-part-you-asked-about)
- [3. `commands/` — slash commands](#3-commands--slash-commands)
- [4. `agents/` — subagents (the biggest usage-saver)](#4-agents--subagents-the-biggest-usage-saver)
- [5. Memory — persistent facts across sessions](#5-memory--persistent-facts-across-sessions)
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

**Rule of thumb:** only put _stable, always-relevant_ instructions here. Anything
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

**Honesty note on `deny`:** rules are *prefix* matches, so `Bash(rm -rf:*)`
misses `rm -fr` / `rm -r -f`, and `Bash(git push --force:*)` misses
`git push -f`. Treat the deny list as a free tripwire for the canonical
spellings, not protection. The robust guard here is a `PreToolUse` hook
(`.claude/hooks/block_destructive.py`) that tokenizes each Bash command
(quote-aware — a commit message *mentioning* `rm -rf` doesn't trip it) and
blocks destructive **intent** in any spelling: recursive+force `rm` at
protected paths (`/`, `~`, `.git`, the workspace root, anything outside the
workspace and `/tmp`), force-pushes to main/master, `git reset --hard`,
`git clean -f`, destructive SQL via a DB client, `dd` to a block device,
`mkfs`. It runs in every permission mode, including bypassPermissions; on an
internal error it fails open but logs to `.claude/logs/hook_errors.log`.

### `hooks`

A **hook** is a shell command **the harness runs automatically** when a specific
event happens during a session. Claude does _not_ decide to run a hook — the
harness fires it on your behalf, every time, deterministically. That's the key
difference from instructions: instructions are suggestions Claude _may_ follow;
hooks are guarantees the harness _will_ execute.

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

| Event              | Fires when…                            | Typical use                          |
| ------------------ | -------------------------------------- | ------------------------------------ |
| `PreCompact`       | Just before context is auto-summarized | Save state so nothing is lost        |
| `PreToolUse`       | Before Claude runs any tool            | Block/validate a command, log it     |
| `PostToolUse`      | After a tool finishes                  | Auto-format edited files, run linter |
| `UserPromptSubmit` | You send a message                     | Inject extra context                 |
| `Stop`             | Claude finishes responding             | Notify you, run tests                |
| `SessionStart`     | A session begins                       | Print project status                 |
| `SubagentStop`     | A subagent finishes                    | Log its task, model, token usage     |

This project uses `PreToolUse` (matcher `Bash`) to block destructive command
variants the deny list's prefix matching can't catch — see the honesty note
under `permissions` above. It also uses `SubagentStop` to log every subagent run — task, model,
token usage, result summary — to `.claude/logs/subagents.jsonl`
(`.claude/hooks/log_subagent.py`, gitignored since it can contain tool
output). Run `.claude/scripts/subagent_summary.py` to tabulate it by model
and agent type — useful for seeing where subagent usage is going.

**Why hooks matter for this project:** the current `PreCompact` hook only does
`echo CONTEXT_SAVE_TRIGGERED`. That echo doesn't save anything — it just prints
a string that Claude is told to watch for and then _manually_ react to. A real
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
any procedure that's needed _sometimes_ — releases, PR creation, status updates —
keeping it out of the always-loaded `CLAUDE.md`.

This project ships: `init`, `cleanup`, `plans`, `pr`, `deploy`, `dev`, `docs`,
`remember`, `backup-memory`. Open any of them —
they're just markdown with a numbered list of steps.

The four project-state procedures (`update-status`, `log`, `status`, `backlog`)
used to live here but are now **skills** (see below): moving a finished item out
of STATUS.md is exactly the step that gets forgotten when it needs a human to
type the command, so those fire automatically at the right moments instead. You
can still invoke them by name (`/update-status` etc.).

To add one: create `commands/foo.md`, write the instructions, and it's available
as `/foo`. No restart needed.

### Slash commands vs. Skills

Claude Code also has a **Skills** feature, and the two are easy to confuse:

|             | Slash command (`commands/*.md`)                      | Skill (`.claude/skills/<name>/SKILL.md`)                                                |
| ----------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Invoked by  | **you**, explicitly typing `/name`                   | **Claude**, automatically, when your request matches the skill's `description`          |
| Best for    | procedures _you_ decide to run (release, PR, status) | capabilities Claude should reach for on its own (e.g. "always lint Terraform this way") |
| Extra files | just the one `.md`                                   | can bundle scripts, templates, reference docs in the skill folder                       |

They're complementary — a command is a manual button, a skill is an
auto-trigger. The slash commands here are procedures you choose to run; the
**bundled skills** in `.claude/skills/` are capabilities Claude reaches for on its
own. Four are the project-state procedures (`update-status`, `log`, `status`,
`backlog`) that manage STATUS.md/CHANGELOG.md — made skills so state upkeep
happens at work-item transitions without being asked. Five more ship vendored
from Jesse Vincent's [Superpowers](https://github.com/obra/superpowers)
collection (MIT — see `.claude/skills/ATTRIBUTION.md`):

- **`using-superpowers`** — teaches Claude to check for and invoke a relevant skill
  before responding.
- **`test-driven-development`** — red-green-refactor discipline (write the failing
  test first).
- **`systematic-debugging`** — find the root cause before proposing any fix.
- **`writing-plans`** — turn a spec into a bite-sized implementation plan (saved to
  `_planning/plans/`).
- **`brainstorming`** — turn an idea into a design/spec via dialogue (saved to
  `_planning/specs/`).

The last two are **modified from upstream**: they _ask before starting_ (upstream
auto-fires and blocks all coding until a design is approved), write to `_planning/`
instead of `docs/superpowers/`, and drop the browser-based "visual companion."
Details in `ATTRIBUTION.md`.

Add your own by dropping a folder with a `SKILL.md` here (its `description`
frontmatter is what Claude matches against). For the full, auto-updating Superpowers
set instead of these vendored copies, install the plugin (`/plugin marketplace add
obra/superpowers-marketplace`). Subagents (§4) are a third, separate thing — a
_whole separate Claude_ you delegate a task to, not an instruction set spliced into
the current turn.

---

## 4. `agents/` — subagents (the biggest usage-saver)

A **subagent** is a _separate_ Claude instance that the main Claude can hand a
task to. It runs with its own fresh context window, does the work, and returns
only a short summary to the main conversation.

Why this saves usage: imagine you ask "find everywhere we call the payments API."
Without a subagent, the main Claude reads 30 files into _your_ context window —
all those tokens now ride along on every later message. With a subagent, that
reading happens in a throwaway context, and only the 5-line answer comes back.
Your main context stays small and cheap.

A subagent is defined by a markdown file with frontmatter:

```markdown
---
name: explore-via-sonnet
description: Read-only codebase search. Use for "where is X" / "how does Y work"
  questions that require reading many files.
model: sonnet # optional — run the subagent on a cheaper/faster model
tools: Read, Grep, Glob # optional — restrict what it can do
---

You are a code exploration agent. Search thoroughly, read only what's needed,
and return a concise answer with file:line references. Do not modify files.
```

Save that as `agents/explore-via-sonnet.md` and the main Claude can delegate to it.

The `model:` frontmatter is only a *default* — the main Claude can override it
per invocation (the Agent tool takes a `model` parameter), so one definition
serves several price points. Ask in plain language ("review this with sonnet")
and the override gets passed.

This boilerplate ships four by default — the highest-impact change for the
"reduce usage" goal:

- **`explore-via-sonnet`** — read-only fan-out searches ("where is X", "how does
  Y work") on a cheaper model; keeps heavy reading out of the main context.
- **`review-diff`** — review a diff for bugs and return a prioritized findings
  list. Defaults to Haiku (review output is small; the reading dominates);
  override to Sonnet for risky or subtle changes.
- **`implement-scoped`** — implement a precisely specced, self-contained change
  (files named, acceptance criteria given); runs lint/tests on what it touched
  and returns a diffstat plus what it verified. Defaults to Sonnet; override to
  Haiku for mechanical multi-file edits. Not for work needing conversation
  context — a subagent starts cold, so you'd pay to re-explain it.
- **`docs-updater`** — checks whether docs need updating after a change and
  edits them only if it's user-facing; used by `/docs`.

---

## 5. Memory — persistent facts across sessions

A place for Claude to write durable notes (one fact per file) that survive
`/clear` and compaction. An index file (`MEMORY.md`) lists them so Claude knows
what's available. Use it for project facts that aren't obvious from the code —
decisions, constraints, "why we did it this way." Not for TODOs (those go in
`STATUS.md`) and never for secrets.

**Where it lives — _not_ in this repo.** Memory is stored in Claude's config
directory, namespaced per project:
`$CLAUDE_CONFIG_DIR/projects/<repo-path-with-slashes-as-dashes>/memory/`
(e.g. `/home/node/.claude/projects/-workspace/memory/`). The repo's working
tree never contains a live `memory/` folder — only the cold snapshot at
`_planning/memory-backup/` (§6) does.

**Why that matters in a dev container.** `$CLAUDE_CONFIG_DIR` is a _named Docker
volume_ (`claude-code-config-…`, see `.devcontainer/devcontainer.json`), not the
host disk. It survives container rebuilds but is wiped by `docker volume prune`,
a Docker Desktop reset, or a `devcontainerId` change. That's exactly why
**`/backup-memory`** mirrors it into the bind-mounted repo at
`_planning/memory-backup/` — the only copy that lives on your host disk.

---

## 6. How the project-state files relate (set by `CLAUDE.md`)

This boilerplate's `CLAUDE.md` defines a convention worth knowing. An item _moves_
between homes (backlog → "In Progress" → CHANGELOG), deleted from the previous one —
never copied.

- **`CLAUDE.md`** — stable only (commands, architecture). Changes rarely.
- **`_planning/STATUS.md`** — the single **living** state file, with three sections:
  - **In Progress** — ≤3 truly active items (_now_).
  - **Blockers** — anything stuck or waiting on input (_now_).
  - **Backlog** — the only queue of future work, priority-ordered; the top
    High-Priority item is "next up" (_future_).
  It's **gitignored by default** — your working status and backlog are private,
  not pushed to a (possibly public) remote. `/init` asks per-project whether to
  make it public (commit it) instead.
- **`CHANGELOG.md`** — _past_: the only completion record, and the public one.
- **`_planning/`** — also holds saved plans (`plans/`), design specs (`specs/`),
  and a cold memory snapshot (`memory-backup/`, written by `/backup-memory` as a
  failsafe against Docker volume loss; read only on demand).

**Why the backlog lives inside STATUS.md** (not a separate `_planning/backlog.md`):
a status file goes stale when "In Progress" drifts from reality. Putting the queue
in the same file means you can't open it to grab the next item without seeing — and
fixing — what's stale. One living file beats two that fall out of sync. `CHANGELOG.md`
stays separate because the past grows unbounded and would bloat the live file.
Two things flag staleness: a `SessionStart` hook prints STATUS.md's age at the top
of each session when it goes cold, and `/status` checks its "Last updated" date.

The other point: keep fast-changing stuff _out_ of `CLAUDE.md` so you're not paying
to load this week's TODO list on every message.

---

## 7. `.devcontainer/` (sibling folder, not under `.claude/`)

Defines the sandboxed Docker environment Claude runs in: the image
(`Dockerfile`), a network firewall (`init-firewall.sh`), and editor/mount config
(`devcontainer.json`). You generally only touch this when changing the runtime
environment, not day-to-day.

**What "running in a container" actually means** (Claude is told this in
`CLAUDE.md` too, since it trips people up):

- **Two kinds of storage.** `/workspace` is a **bind mount** — the same files on
  your host disk, so edits and commits land directly in your repo.
  `/home/node/.claude` (`$CLAUDE_CONFIG_DIR`) is a **named Docker volume** — it
  persists across rebuilds but is _not_ on the host disk, so `docker volume
prune` / a Docker Desktop reset / a `devcontainerId` change wipes it. Memory
  (§5) and session history live there; `/backup-memory` is the failsafe.
- **No host browser, and ports are forwarded, not shared.** A dev server must
  bind `0.0.0.0` (not `127.0.0.1`) to be reachable from the host. There's no
  `forwardPorts` pinned, so the editor **auto-forwards each container port to a
  free host port** — the host port may differ from the container port, and that
  dynamic assignment is exactly what lets several of these containers run in
  parallel without colliding. Don't hardcode a host port, and don't try to open
  a browser from inside the container — surface the URL and let the user open it
  from the editor's **Ports** panel. (`/dev` follows this.)

---

## Editing cheatsheet

| I want to…                                      | Edit…                                                                |
| ----------------------------------------------- | -------------------------------------------------------------------- |
| Add an always-on rule                           | `CLAUDE.md` (sparingly!)                                             |
| Auto-approve a safe command                     | `settings.json` → `permissions.allow`                                |
| Make something happen automatically on an event | `settings.json` → `hooks`                                            |
| Add a reusable `/procedure`                     | new file in `commands/`                                              |
| Offload heavy reading to save context           | new file in `agents/`                                                |
| Record a durable project fact                   | use `/remember` (writes to Claude's config-dir memory, not the repo) |
