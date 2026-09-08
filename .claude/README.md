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
> | Status line | `scripts/usage-statusline.sh` (via `settings.json`) | Every response | The harness |

## Contents

- [1. `CLAUDE.md` — always-on instructions](#1-claudemd--always-on-instructions)
- [2. `settings.json` — permissions and hooks](#2-settingsjson--permissions-and-hooks)
  - [`permissions`](#permissions)
  - [`hooks` — the part you asked about](#hooks--the-part-you-asked-about)
- [3. `commands/` — slash commands](#3-commands--slash-commands)
- [4. `agents/` — subagents (the biggest usage-saver)](#4-agents--subagents-the-biggest-usage-saver)
  - [Parallel work: git worktrees](#parallel-work-git-worktrees)
- [5. Memory — persistent facts across sessions](#5-memory--persistent-facts-across-sessions)
- [6. How the project-state files relate (set by `CLAUDE.md`)](#6-how-the-project-state-files-relate-set-by-claudemd)
- [7. `.devcontainer/` (sibling folder, not under `.claude/`)](#7-devcontainer-sibling-folder-not-under-claude)
- [8. Boilerplate detection & lifecycle (origin vs. copy)](#8-boilerplate-detection--lifecycle-origin-vs-copy)
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

**Two CLAUDE.md files, one rule of precedence.** Claude Code loads both the
root `CLAUDE.md` and `.claude/CLAUDE.md`. In this harness they have different
owners:

- `.claude/CLAUDE.md` is the **harness**: synced verbatim from the boilerplate
  by `sync-harness.sh`, never edited per project.
- The root `CLAUDE.md` is the **project's**: its own commands and
  architecture notes, plus a `## Harness settings` section holding the
  recorded choices (`Harness:`, `STATUS.md:`, `Commit policy:`,
  `Testing policy:`, `Commit session links:`, `Review page:`) and any
  deviation from a harness rule — "STATUS.md is tracked at `./STATUS.md` so
  contributors see it", "`.claude/` is gitignored here; it's personal
  tooling". **Where the two disagree, the root file wins.** Claude is told
  this in `.claude/CLAUDE.md` itself, so a deviation is a setting, not a
  contradiction to raise. `/init` writes the section; a refresh sync moves
  any lines that older copies still had inside `.claude/CLAUDE.md`.

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
misses `rm -r -f`, `rm --recursive --force` and `cd /tmp && rm -rf ~`, and
`Bash(git push --force:*)` misses `git push origin --force`. Treat the deny list as a free tripwire for the canonical
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

This project uses `PreToolUse` (matcher `Bash`) for three hooks. The first
blocks destructive command variants the deny list's prefix matching can't
catch — see the honesty note under `permissions` above. The second
(`socket_scan.py`) routes package installs through
[Socket](https://socket.dev)'s scanner: it blocks a plain `npm|npx|pnpm|yarn`
install and tells Claude to re-run it as `socket npm install …`, which audits
the packages before handing off. It is **inert unless you opt in** — it needs
both a `socket` binary on PATH and `SOCKET_CLI_API_TOKEN` set, neither of
which the boilerplate ships, because Socket needs an account and uploads your
dependency manifest to a third party. `/init` asks; `.devcontainer/STACKS.md`
§Active scanning (Socket) has the full picture, including why `socket` itself
is exempt from the age gate. Set `SOCKET_HOOK=off` to silence it. Note the
scope: it covers what *Claude* runs, not what you type in a terminal and not
a `git pull` that changes a lockfile — those need a CI step. The third
(`bounded_reads.py`) blocks a bare `cat` of a file over ~250 lines / 20 KB
unless its output is piped, and tells Claude the size and the bounded forms
(`grep -n … | head`, `sed -n 'A,Bp'`) to use instead. Every Bash result stays
in context for the rest of the session, and unbounded `cat` of a 65 KB
STATUS.md or whole component files "for 20 lines" was the single largest
avoidable cost measured in a downstream project — this makes CLAUDE.md's
"read bounded" rule a guarantee rather than advice. `BOUNDED_READS=off`
disables it; `BOUNDED_READS_MAX_LINES` / `_MAX_BYTES` tune it.

It also uses `SubagentStop` to log every subagent run — task, model,
token usage, result summary — to `.claude/logs/subagents.jsonl`
(`.claude/hooks/log_subagent.py`, gitignored since it can contain tool
output). Run `.claude/scripts/subagent_summary.py` to tabulate it by model
and agent type — useful for seeing where subagent usage is going. Interim
stop events with no token usage aren't logged (they're polling noise, not
runs); `--prune` deletes any accumulated by older hook versions — the
script's docstring explains both.

**Why hooks matter for this project:** the `PreCompact` hook
(`save-context.sh`) writes a timestamped marker into `STATUS.md` itself *and*
echoes `CONTEXT_SAVE_TRIGGERED` for Claude to react to — so the deterministic
part happens even if Claude misses the cue. Hooks are how you turn "Claude
usually remembers to X" into "X always happens." (SessionStart hooks also
check `.boilerplate-dev` — a gitignored root marker identifying the
boilerplate's own dev repo — so first-run detach nudges never fire here while
still shipping to copies.)

A practical example you might add — auto-format every file Claude edits:

```jsonc
"PostToolUse": [
  { "matcher": "Edit|Write",
    "hooks": [ { "type": "command",
      "command": "npx prettier --write \"$CLAUDE_FILE_PATHS\" 2>/dev/null || true" } ] }
]
```

### `statusLine`

`settings.json` also wires `.claude/scripts/usage-statusline.sh` as the status
line: `5h 12% · resets 17:46 │ 7d 41% · resets Wed 12:26 │ ctx 37%`. The two
rate-limit windows come from Claude.ai Pro/Max sessions (absent until the first
response; the line shows only `ctx` before then), and `ctx` is how full the
current context window is — the number that says when to `/clear` or
`/compact`. It runs locally, needs `jq`, and never enters the model context.
Reset times print in `$TZ`; set it in your gitignored `settings.local.json`
(`"env": { "TZ": "Area/City" }`) or they show as UTC.

---

## 3. `commands/` — slash commands

Each `.md` file here becomes a `/command`. When you type `/cleanup`, the harness
loads `commands/cleanup.md` and feeds it to Claude as instructions **for that one
turn**. When you don't use it, it costs nothing.

Think of commands as "scripts written in English." They're the right home for
any procedure that's needed _sometimes_ — releases, PR creation, status updates —
keeping it out of the always-loaded `CLAUDE.md`.

This project ships: `init`, `cleanup`, `plans`, `pr`, `dev`, `docs`,
`remember`, `backup-memory`, `socratic` (`/socratic <decision>` stress-tests a
design with questions instead of answers; `/socratic teach <topic>` tutors you
toward your own answer — a command rather than a skill on purpose, since only
you know when you want to be questioned instead of answered). Open any of them —
they're just markdown with a numbered list of steps.

The four project-state procedures (`update-status`, `log`, `status`, `release`)
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
`release`) that manage STATUS.md/CHANGELOG.md — made skills so state upkeep
happens at work-item transitions without being asked. Five more ship vendored
from Jesse Vincent's [Superpowers](https://github.com/obra/superpowers)
collection (MIT — see `.claude/skills/ATTRIBUTION.md`):

- **`using-superpowers`** — teaches Claude to check for and invoke a clearly
  relevant skill before starting, and that user instructions always win.
- **`test-driven-development`** — red-green-refactor discipline (write the failing
  test first). Fires only when the project opts in via `Testing policy: tdd`
  in its CLAUDE.md, or when you ask for tests-first.
- **`systematic-debugging`** — find the root cause before proposing any fix.
- **`writing-plans`** — turn a spec into a bite-sized implementation plan (saved to
  `_planning/plans/`).
- **`brainstorming`** — turn an idea into a design/spec via dialogue (saved to
  `_planning/specs/`).

All but `systematic-debugging` are **modified from upstream**, in the same
direction: opt-in over auto-fire. `writing-plans`/`brainstorming` _ask before
starting_ (upstream auto-fires and blocks all coding until a design is approved)
and write to `_planning/` instead of `docs/superpowers/`;
`test-driven-development` is gated on the per-project testing policy instead of
firing on every feature; `using-superpowers` drops upstream's "1% chance →
MUST invoke" dispatch rule. Details in `ATTRIBUTION.md`.

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

### Parallel work: git worktrees

Subagents share one working tree, so they must not edit files at the same time —
fine for the read-only and hand-off-then-wait patterns above, wrong for running
two coding tasks *concurrently*. A **git worktree** gives each agent its own
checkout of the same repo (one `.git`, many working directories on different
branches), so parallel edits can't collide.

Claude Code creates and manages them itself — you rarely need `git worktree`
by hand. Three ways, most common first:

- **A whole session in a worktree: `claude --worktree <name>`** (`-w`). Start
  Claude this way for a second terminal working a parallel task. It creates
  `.claude/worktrees/<name>/` on a fresh branch `worktree-<name>` (from the
  default branch; `worktree.baseRef: "head"` in settings branches from your
  current HEAD, and `claude -w "#123"` starts from a PR). On exit it removes a
  clean worktree and asks whether to keep one that has changes. Mid-session,
  asking Claude to "work in a worktree" does the same via its `EnterWorktree`
  tool. (Verified 2026-09-04: the path and branch name above are what the
  current CLI produces.)
- **Subagents: `isolation: "worktree"`.** Claude launches a parallel agent
  into a throwaway worktree and cleans it up if nothing changed. No path or
  lifecycle to manage. This is the tool for "run these two edits concurrently".
- **Manual `git worktree add`**, only for something the above don't cover
  (e.g. a long-lived worktree on an existing branch):

  ```sh
  git worktree add .claude/worktrees/<name> <existing-branch>   # create
  git worktree list                                             # see them
  git worktree remove .claude/worktrees/<name>                  # when merged
  git worktree prune                                            # dangling refs
  ```

**Keep worktrees inside the repo — never `../sibling` dirs.** The dev
container bind-mounts only `/workspace` (§7), so a worktree created outside it
— which `git worktree add ../foo`, the usual tutorial default, does — is
invisible inside the container. Claude Code's default `.claude/worktrees/` is
already inside; use it for manual ones too so there's one place to look. It is
**not** auto-ignored by Claude Code, so `.gitignore` lists it (plus the older
`.worktrees/`); because the ignore is shared through the one `.git`, worktrees
don't recursively see each other either. Files that are gitignored but needed
in every worktree (`.env`, local settings) can be listed in a
`.worktreeinclude` file at the repo root, gitignore syntax, and Claude Code
copies them in. (On the *host*, outside any container, a sibling dir is fine —
the constraint is the mount, not git.)

Two things worktrees do **not** share: installed dependencies and build output.
Each worktree needs its own `npm install` / equivalent (with this repo's
`.npmrc`, still no install scripts). And they *do* share branches and stashes —
two worktrees can't check out the same branch at once, which is a feature: it
stops two agents landing on top of each other. Merge the finished branch back
the normal way, then `git worktree remove` — a dangling worktree holds a branch
checked out and blocks reusing it.

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
- **`_planning/STATUS.md`** — the single **living** state file, with four sections:
  - **In Progress** — ≤3 truly active items (_now_).
  - **Needs input** — decisions or reviews waiting on *you*, never mixed into
    In Progress. Past four items they move, with full context, to
    `_planning/REVIEW.md` (same gitignore status) and STATUS.md keeps one
    pointer line. `/review` renders them as a click-through page
    (`_planning/review.html`: Approve / Needs change / Reject + notes per
    item, "Copy decisions" gives you a markdown block to paste back). The
    `Review page: on | off` line in CLAUDE.md says whether Claude regenerates
    it on its own after every status edit; off by default, since that is a
    tool call per edit.
  - **Blockers** — anything stuck on external events (_now_).
  - **Backlog** — the only queue of future work, priority-ordered; the top
    High-Priority item is "next up" (_future_).
  It's **gitignored by default** — your working status and backlog are private,
  not pushed to a (possibly public) remote. `/init` asks per-project whether to
  make it public (commit it) instead.
- **`CHANGELOG.md`** — _past_: the only completion record, and the public one.
- **`_planning/`** — also holds saved plans (`plans/`), design specs (`specs/`),
  and a cold memory snapshot (`memory-backup/`, written by `/backup-memory` as a
  failsafe against Docker volume loss; read only on demand). **A plan is not a
  queue**: it records the approach and the decisions (what was rejected and
  why, what was measured — the part `git log` can't reconstruct). Its
  checkboxes are a scratchpad while it's being executed; when work pauses, the
  remainder moves to STATUS.md. A plan carrying its own open-item list is a
  second copy of the queue, and the second copy is the one that rots — a
  downstream repo retired one with 28 open boxes, 25 of them describing work
  that had shipped, and it had been believed.

**Why the backlog lives inside STATUS.md** (not a separate `_planning/backlog.md`):
a status file goes stale when "In Progress" drifts from reality. Putting the queue
in the same file means you can't open it to grab the next item without seeing — and
fixing — what's stale. One living file beats two that fall out of sync. `CHANGELOG.md`
stays separate because the past grows unbounded and would bloat the live file.
Two things flag staleness: a `SessionStart` hook prints STATUS.md's age at the top
of each session when it goes cold, and `/status` checks its "Last updated" date.
A sibling hook, `plan-staleness-check.sh`, does the same for plans: an open
plan that three or more commits have landed against since it was last touched
prints `PLAN_DRIFT` — the cue to check each box against the tree, move what
survives to STATUS.md, and retire the plan. It's the backstop; the rule above
is the fix.

The other point: keep fast-changing stuff _out_ of `CLAUDE.md` so you're not paying
to load this week's TODO list on every message.

---

## 7. `.devcontainer/` (sibling folder, not under `.claude/`)

Defines the sandboxed Docker environment Claude runs in: the image
(`Dockerfile`), a network firewall (`init-firewall.sh` — logic only; the domain
allowlist is the data file `allowed-domains.txt`), shell shortcuts
(`claude-harness.zsh`: `cc`/`ccc`/`ccr`/`ccw`, `cc-help` lists them), and
editor/mount config (`devcontainer.json`). You generally only touch this when changing the runtime
environment, not day-to-day. Project-specific Dockerfile layers go **below**
the `# ==== PROJECT LAYERS ====` marker: `scripts/sync-harness.sh` replaces
everything above it with the boilerplate's version on refresh and keeps what's
below.

**What "running in a container" actually means** (Claude is told this in
`CLAUDE.md` too, since it trips people up):

- **Two kinds of storage.** `/workspace` is a **bind mount** — the same files on
  your host disk, so edits and commits land directly in your repo.
  `/home/node/.claude` (`$CLAUDE_CONFIG_DIR`) is a **named Docker volume** — it
  persists across rebuilds but is _not_ on the host disk, so `docker volume
prune` / a Docker Desktop reset / a `devcontainerId` change wipes it. Memory
  (§5), session history, and your Claude sign-in live there; `/backup-memory`
  is the failsafe for memory, and a wipe just means signing in again.
- **No host browser, and ports are forwarded, not shared.** A dev server must
  bind `0.0.0.0` (not `127.0.0.1`) to be reachable from the host. There's no
  `forwardPorts` pinned, so the editor **auto-forwards each container port to a
  free host port** — the host port may differ from the container port, and that
  dynamic assignment is exactly what lets several of these containers run in
  parallel without colliding. Don't hardcode a host port, and don't try to open
  a browser from inside the container — surface the URL and let the user open it
  from the editor's **Ports** panel. (`/dev` follows this.)
- **Never add `appPort` or a `-p` runArg to `devcontainer.json`.** It fights
  the dynamic forwarding above, and Docker treats `"3000:3000"` and
  `"0.0.0.0:3000:3000"` as *distinct* mappings — list both (easy to do across
  `appPort` and `runArgs`) and the container conflicts with **itself** at
  startup: `bind: address already in use` while `lsof -iTCP:3000` on the host
  shows nothing, because no external process holds the port. If you saw that
  error with an empty lsof, this is what happened.
- **A container that "won't start" has a second, unrelated cause:**
  `"waitFor": "postStartCommand"` means a failing `init-firewall.sh` (e.g. a
  typo'd domain that won't resolve) blocks the container from ever becoming
  ready. Distinguish them by the log: port conflicts fail at `docker run`,
  firewall failures fail after it, in the postStart output.

---

## 8. Boilerplate detection & lifecycle (origin vs. copy)

This repo ships as a template, so the harness has to tell two situations apart:
**this repo** (the boilerplate's own dev repo, where template files and history
are the product) and a **copy** made from it to start a real project (where those
same files are cruft that should be detached). Getting it wrong is annoying in
one direction (nagging you here forever) and harmful in the other (a copy that
silently keeps the template's README/LICENSE/git history).

**Two signals do the work — one that ships, one that doesn't:**

- **Container name** `"Claude Boilerplate Repo"` in `.devcontainer/devcontainer.json`
  is **committed**, so every copy inherits it. It's the durable "not set up yet"
  flag: `/init` and `scripts/new-project.sh` rename it to the real project, so the
  default name still being present means "nobody has detached this copy." More
  durable than a file that could be deleted, and it survives cloning.
- **`.boilerplate-dev`** is a root marker that is **gitignored**, so clones and
  copies never receive it. Its presence means "this is the origin — suppress the
  detach machinery." It's the *only* thing that distinguishes the origin from an
  un-detached copy, since both carry the default container name.

**Three consumers read them:**

| Consumer | When | With marker (origin) | Without marker (copy) |
| --- | --- | --- | --- |
| `hooks/first-run-check.sh` | SessionStart, automatic | silent | prints the `FIRST_RUN_BOILERPLATE` nudge while the container name is still the default |
| `scripts/new-project.sh` | you run it | refuses (won't reset origin history) | detaches: renames README → BOILERPLATE.md, deletes LICENSE, resets history, renames container, self-deletes |
| `/init` | you run it | skips detach offer + container rename | offers detach (copy) or gap-fills (installed harness) |

**The flows, including the edge cases:**

- **Working on this repo (origin).** Marker present → no nag, `new-project.sh`
  refuses, `/init` skips detach/rename. Nothing to do.
- **Fresh clone of *this* repo to hack on the boilerplate itself.** The marker is
  gitignored, so a clone **doesn't have it** — you now look like an un-detached
  copy: you'll get the first-run nudge and `new-project.sh` would happily detach.
  Fix is one line, and `.boilerplate-dev` documents it itself: `touch .boilerplate-dev`.
  This is the one rough edge of the design — the origin signal isn't intrinsic, so
  it has to be re-created after a clone.
- **Normal copy via `scripts/new-project.sh`.** The script renames the container
  and deletes itself, so detection turns off cleanly and the new project starts
  with its own identity. The intended happy path.
- **Copy *without* the script** (`degit`, "Use this template", manual copy). No
  marker (gitignored, never travels) and the container keeps the default name →
  the first-run nudge fires every session until you detach. Running `/init` (offers
  detach → runs `new-project.sh`) or `new-project.sh` directly resolves it.
- **Copy where nobody renames the devcontainer.** By design the nudge keeps firing
  each session — that's the persistent signal, not a bug. It's harmless (just a
  reminder) but won't stop until the name changes, via `/init`, `new-project.sh`,
  or editing `devcontainer.json` by hand. Renaming is what flips "un-detached copy"
  to "set-up project."
- **Harness installed into an existing codebase** (`sync-harness.sh` install mode).
  The copied `devcontainer.json` carries the default name, so the same nudge fires
  there — correctly, since `/init` still needs to gap-fill (`.gitignore`, `_planning/`,
  policies) and rename. No marker is involved; it's just another un-set-up copy.

**Why keep the whole mechanism rather than trim it:** the marker must exist anyway
for the SessionStart hook, so the `/init`/`new-project.sh` guards that read it are
nearly free. The container-rename skip is the load-bearing one — it's the only guard
stopping a stray `/init` in this repo from renaming the container and, if committed,
silently breaking first-run detection for every downstream copy.

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
