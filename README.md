# Claude Project Boilerplate

A starting point for new projects worked on with **Claude Code**. It ships a
preconfigured `.claude/` harness (instructions, permissions, slash commands,
subagents, hooks) and a sandboxed dev container, tuned for two goals:

- **Lower token usage** — a lean always-on `CLAUDE.md`, subagents that keep heavy
  reading out of the main context, and targeted-read conventions.
- **Approachable** — written so a junior dev, or even a non-dev, can follow it:
  plain-language docs over cleverness, with every moving part explained in
  [`.claude/README.md`](.claude/README.md).

The **harness** is not tied to one stack or programming language: commands detect
Node, Python, Rust, Go, and Make-based projects out of the box, and permissions
cover those toolchains. The **dev container**, though, is Node-first: only the
Node toolchain is preinstalled, and its firewall passes only npm's registry.
Any other stack is one documented rebuild away —
[`.devcontainer/STACKS.md`](.devcontainer/STACKS.md) has the recipe (toolchain +
exact firewall domains + verification) for Python, Go, Rust, Java, and Ruby, and
the pattern for everything else (Solidity/Foundry, Elixir, Zig, …). For the
smoothest ride also add your toolchain to the `settings.json` allowlist and the
detection lists in `/dev` and `/cleanup` (each is a small markdown edit).

It also runs inside a **Dev Container** — a reproducible, network-restricted
sandbox. See [Dev Container](#dev-container) below.

> **New here? Start with [`.claude/README.md`](.claude/README.md)** — it explains
> the whole harness (hooks, subagents, commands, memory, state files) in plain
> language, no prior Claude Code experience assumed.

## Contents

- [What's inside](#whats-inside)
- [Getting started](#getting-started)
- [Dev Container](#dev-container)
  - [The firewall (`init-firewall.sh`)](#the-firewall-init-firewallsh)
- [Conventions](#conventions)
- [License](#license)

## What's inside

```
.claude/
├── CLAUDE.md          # Always-on project instructions (kept deliberately short)
├── README.md          # ★ Guide to the harness — read this first
├── settings.json      # Permissions (allow/deny) + hooks (PreToolUse guard, PreCompact, SubagentStop)
├── commands/          # Slash commands: /init /cleanup /plans /pr /socratic …
├── agents/            # Subagents: explore-via-sonnet (search), review-diff, implement-scoped, docs-updater
├── skills/            # Auto-invoked skills: project-state upkeep (update-status, log, status, backlog), TDD, systematic-debugging, writing-plans, brainstorming, using-superpowers
├── scripts/           # subagent_summary.py — tabulates the SubagentStop log
└── hooks/             # block_destructive.py (guards rm -rf/force-push variants), save-context.sh (pre-compaction), log_subagent.py (logs subagent runs)
.devcontainer/         # Sandboxed Docker env + network firewall (see below)
.npmrc                 # Supply-chain hardening: no install scripts, exact pins (see STACKS.md §Supply-chain hardening — incl. pnpm/cargo/go equivalents)
LICENSE                # MIT
```

**Bundled skills** (in `.claude/skills/`) work out of the box — Claude Code
auto-discovers any `.claude/skills/<name>/SKILL.md` at session start and Claude
invokes the matching one itself; there's nothing to install or call manually.
Four manage project state (`update-status`, `log`, `status`, `backlog`): they
fire when work starts, completes, or blocks, so finished items actually leave
STATUS.md instead of waiting for someone to run a command (you can still type
`/update-status` etc.). Five more ship vendored from [Superpowers](https://github.com/obra/superpowers)
(MIT — see `.claude/skills/ATTRIBUTION.md`): `test-driven-development`,
`systematic-debugging`, `using-superpowers` (which nudges Claude to reach for a
relevant skill before answering), plus `writing-plans` and `brainstorming`. All
but `systematic-debugging` are modified from upstream to be **opt-in rather than
auto-firing**: plans/brainstorms ask before starting and save under `_planning/`,
TDD applies only when the project records `Testing policy: tdd` (a per-project
choice, asked once — like the commit policy), and the skill dispatcher drops
upstream's "1% chance → MUST invoke" rule. Delete a folder to remove that
skill; install the Superpowers _plugin_
instead if you'd rather track the full, unmodified, auto-updating upstream set.

## Getting started

Two ways in, depending on whether your project already exists.

### Path A — start a new project from this repo

1. **Copy this repo** as the seed for your new project (or use it as a template).
2. Open it in the dev container (VS Code: "Reopen in Container") or your own env.
3. Run **`/init`** in Claude Code. It offers to detach the boilerplate first
   (`scripts/new-project.sh` — removes this README/LICENSE, resets state files,
   drops the boilerplate's git history), then detects your stack and scaffolds
   `README.md`, `CHANGELOG.md`, `.gitignore`, `.gitattributes`, and `_planning/`
   (including `_planning/STATUS.md`, your living status + backlog — gitignored by
   default; `/init` asks whether to make it public). Then add your project's own
   `LICENSE`.

### Path B — add the harness to an existing codebase

Don't copy the whole repo into an existing project — its README, LICENSE, and
git history would collide with yours. Instead, from a checkout of this repo **on
the host** (not inside a container; sibling directories aren't visible there):

```sh
scripts/sync-harness.sh ../your-project
```

When the target has no `.claude/` yet, the script runs in **install mode**:
after one confirmation it copies `.claude/` and `.devcontainer/` — and nothing
else. Your `.git`, code, and README are never touched. (It also strips this
repo's recorded commit/testing policies from the copied `CLAUDE.md` so `/init`
asks you fresh.) Then reopen the project in its dev container and run
**`/init`**: it fills gaps without overwriting — merges the required
`.gitignore` entries into your existing one, scaffolds `_planning/`, renames
the container, records your policies, and flags non-Node stacks (the container
ships Node-only; recipes in [`.devcontainer/STACKS.md`](.devcontainer/STACKS.md)).

Re-run the same command later to pull harness updates into the project
(**refresh mode**: mirrors commands/skills/agents/hooks, confirms deletions,
and diff-asks before touching files that hold per-project edits, such as
firewall domains or the container name).

Already have a `.claude/` setup you want rid of — a hand-rolled harness, or
conventions worth abandoning? `scripts/sync-harness.sh --replace ../your-project`
backs the old `.claude/` + `.devcontainer/` up to a timestamped `tar.gz` at the
project root, then installs fresh. To replace just one file's conventions
(say, a sloppy `CLAUDE.md`), plain refresh mode is enough: answer `y` at that
file's diff prompt.

### Then, either way

Start building. Work is tracked for you — the `update-status`/`log` skills
fire as items start and finish (`/status` any time for a summary). Use
`/cleanup` before commits, and `/pr` to open pull requests.

**Tip: for anything non-trivial, start in Plan Mode.** Press **Shift+Tab** to
cycle the input mode (normal → auto-accept → **plan**), or launch with
`claude --permission-mode plan`. In Plan Mode Claude researches and proposes a
plan _without editing files_ until you approve it; on approval it saves the plan
to `_planning/plans/YYYY-MM-DD-name.md` and starts work. Good for features,
refactors, or anything you'd want to review before code changes.

New to how any of this works? Read [`.claude/README.md`](.claude/README.md) — it
explains hooks, subagents, commands, and the state-file convention in plain terms.

## Dev Container

This repo ships a [**Dev Container**](https://containers.dev/) (`.devcontainer/`).
A dev container is a Docker-based development environment defined in code: anyone
who opens the repo gets the _exact_ same OS, tools, and settings, with no
"works on my machine" drift. VS Code ("Reopen in Container"), GitHub Codespaces,
and the `devcontainer` CLI all understand it.

Why it matters here: Claude Code runs shell commands, so a disposable, isolated
container is a safer place for it to work than your host machine.

> **Not for iOS/macOS-native development.** Dev containers are Linux — Xcode,
> the iOS SDK, simulators, and code signing only exist on macOS, so no image
> tweak makes a native iOS/macOS app buildable in here (React Native/Flutter
> hit the same wall at `pod install`/simulator time). For those projects, drop
> `.devcontainer/` and use the `.claude/` harness directly on your Mac — the
> hooks, skills, and agents are plain bash/python and fully portable; you lose
> the container's isolation and firewall, but the deny list and the
> `block_destructive.py` guard still run. Release builds belong on macOS CI
> runners (GitHub Actions `macos-*`, Xcode Cloud) either way.

**What this container sets up** (`.devcontainer/`):

| File                | Purpose                                                                                                                                                                                                        |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Dockerfile`        | Base image `node:20` + dev tools (`git`, `gh`, `zsh`, `fzf`, `jq`, `delta`, `iptables`/`ipset`). Installs Claude Code globally and runs as the non-root `node` user.                                           |
| `devcontainer.json` | Editor setup (ESLint, Prettier, GitLens, format-on-save), zsh as default shell, persistent bash history + `~/.claude` config via named volumes, and the `NET_ADMIN`/`NET_RAW` capabilities the firewall needs. |
| `init-firewall.sh`  | A **default-deny network firewall**, run on container start.                                                                                                                                                   |
| `STACKS.md`         | Recipes for adding non-Node stacks (Python, Go, Rust, Java, Ruby): toolchain install + exact firewall domains + a verification step. The container ships Node-only until one is applied.                       |

> **Rename the container for your project.** The `"name"` in `devcontainer.json`
> ships as `"Claude Boilerplate Repo"`. Change it to your project's name — it
> labels the container in Docker/VS Code (handy when several of these run in
> parallel), and the default name is what the first-run hook keys off to detect a
> copy that hasn't been set up yet. `/init` and `scripts/new-project.sh` rename it
> for you; if you set things up by hand, change it yourself.
> (Working on the boilerplate _itself_? Keep the default name — it has to ship
> to copies — and `touch .boilerplate-dev` instead: that gitignored marker,
> which clones never inherit, silences the first-run nag and makes
> `new-project.sh` and `/init` refuse to detach/rename this repo.)

### The firewall (`init-firewall.sh`)

On startup the container locks down outbound network traffic to a small
allowlist, so commands Claude runs can't reach arbitrary hosts:

- **Allowed:** GitHub (IP ranges pulled live from `api.github.com/meta`), the npm
  registry, `api.anthropic.com`, the VS Code marketplace, and telemetry endpoints
  (`sentry.io`, `statsig.com`), plus DNS, SSH, localhost, and the host LAN.
- **Blocked:** everything else outbound is `REJECT`ed.
- **Self-verifying:** it confirms `example.com` is unreachable and `api.github.com`
  is reachable, and fails the startup if either check is wrong.

To allow another host, add its domain to the `allowed_domains` array in
`init-firewall.sh` and **rebuild** (the script is baked into the image; editing
the repo copy alone does nothing). Adding a language stack? Use the tested
per-stack domain lists in [`.devcontainer/STACKS.md`](.devcontainer/STACKS.md) —
package managers usually need an index host *and* a separate download host, and
missing one makes installs hang silently. If a tool mysteriously can't reach
the network, the firewall allowlist is the first place to look.

## Conventions

- **`CLAUDE.md`** holds only stable instructions. **`_planning/STATUS.md`** is the
  single living state file — In Progress + Blockers (now) and a Backlog section
  (future, the only queue); **`CHANGELOG.md`** is the past. Items move between
  them, never copied. The backlog lives inside STATUS.md on purpose: it keeps the
  queue next to "In Progress" so the file doesn't go stale. STATUS.md is gitignored
  by default (private working state); `/init` asks whether to make it public.
- **Atomic, conventional commits** (`feat:`, `fix:`, `docs:`, …) so any change can
  be reverted cleanly.
- **Secrets never get committed** — `.env*`, `*.pem`, `*.key` are gitignored by
  `/init`.

## License

[MIT](LICENSE) — do whatever you like; no warranty.
