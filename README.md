# Claude Project Boilerplate

A starting point for new projects worked on with **Claude Code**. It ships a
preconfigured `.claude/` harness (instructions, permissions, slash commands,
subagents, hooks) and a sandboxed dev container, tuned for two goals:

- **Lower token usage** — a lean always-on `CLAUDE.md`, subagents that keep heavy
  reading out of the main context, and targeted-read conventions.
- **Approachable** — written so a junior dev, or even a non-dev, can follow it:
  plain-language docs over cleverness, with every moving part explained in
  [`.claude/README.md`](.claude/README.md).

It is **not tied to one language**: commands detect Node, Python, Rust, Go, and
Make-based projects out of the box, and permissions cover those toolchains.
Other stacks (Solidity/Foundry, Elixir, Zig, …) still work — Claude figures out
the commands — but for the smoothest ride add your toolchain to the
`settings.json` allowlist and the detection lists in `/dev`, `/cleanup`, and
`/deploy` (each is a small markdown edit).

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
├── settings.json      # Permissions (allow/deny) + the PreCompact hook
├── commands/          # Slash commands: /init /cleanup /status /pr /deploy …
├── agents/            # Subagents: explore (read-only search), review (diff review)
└── hooks/             # save-context.sh — runs automatically before compaction
.devcontainer/         # Sandboxed Docker env + network firewall (see below)
LICENSE                # MIT
```

## Getting started

1. **Copy this repo** as the seed for your new project (or use it as a template).
2. Run **`scripts/new-project.sh`** to detach the boilerplate: it renames this
   README to `BOILERPLATE.md`, deletes the boilerplate's `LICENSE`, resets
   `STATUS.md`/`CHANGELOG.md`/`_planning/` to empty templates, and removes
   itself. Add `--fresh-git` to also drop the boilerplate's git history.
3. Open it in the dev container (VS Code: "Reopen in Container") or your own env.
4. Run **`/init`** in Claude Code. It detects your stack and scaffolds
   `README.md`, `STATUS.md`, `CHANGELOG.md`, `.gitignore`, `.gitattributes`, and
   `_planning/`, and initializes git. Then add your project's own `LICENSE`.
5. Start building. Use `/status` and `/update-status` to track work, `/cleanup`
   before commits, and `/pr` to open pull requests.

New to how any of this works? Read [`.claude/README.md`](.claude/README.md) — it
explains hooks, subagents, commands, and the state-file convention in plain terms.

## Dev Container

This repo ships a [**Dev Container**](https://containers.dev/) (`.devcontainer/`).
A dev container is a Docker-based development environment defined in code: anyone
who opens the repo gets the *exact* same OS, tools, and settings, with no
"works on my machine" drift. VS Code ("Reopen in Container"), GitHub Codespaces,
and the `devcontainer` CLI all understand it.

Why it matters here: Claude Code runs shell commands, so a disposable, isolated
container is a safer place for it to work than your host machine.

**What this container sets up** (`.devcontainer/`):

| File | Purpose |
|------|---------|
| `Dockerfile` | Base image `node:20` + dev tools (`git`, `gh`, `zsh`, `fzf`, `jq`, `delta`, `iptables`/`ipset`). Installs Claude Code globally and runs as the non-root `node` user. |
| `devcontainer.json` | Editor setup (ESLint, Prettier, GitLens, format-on-save), zsh as default shell, persistent bash history + `~/.claude` config via named volumes, and the `NET_ADMIN`/`NET_RAW` capabilities the firewall needs. |
| `init-firewall.sh` | A **default-deny network firewall**, run on container start. |

### The firewall (`init-firewall.sh`)

On startup the container locks down outbound network traffic to a small
allowlist, so commands Claude runs can't reach arbitrary hosts:

- **Allowed:** GitHub (IP ranges pulled live from `api.github.com/meta`), the npm
  registry, `api.anthropic.com`, the VS Code marketplace, and telemetry endpoints
  (`sentry.io`, `statsig.com`), plus DNS, SSH, localhost, and the host LAN.
- **Blocked:** everything else outbound is `REJECT`ed.
- **Self-verifying:** it confirms `example.com` is unreachable and `api.github.com`
  is reachable, and fails the startup if either check is wrong.

To allow another host, add its domain to the resolve loop in `init-firewall.sh`.
If a tool mysteriously can't reach the network, the firewall allowlist is the
first place to look.

## Conventions

- **`CLAUDE.md`** holds only stable instructions. State files own one tense
  each — `STATUS.md` = now, `_planning/backlog.md` = future (the only queue),
  `CHANGELOG.md` = past — and items move between them, never copied.
- **Atomic, conventional commits** (`feat:`, `fix:`, `docs:`, …) so any change can
  be reverted cleanly.
- **Secrets never get committed** — `.env*`, `*.pem`, `*.key` are gitignored by
  `/init`.

## License

[MIT](LICENSE) — do whatever you like; no warranty.
