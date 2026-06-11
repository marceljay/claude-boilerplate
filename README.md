# Claude Project Boilerplate

A starting point for new projects worked on with **Claude Code**. It ships a
preconfigured `.claude/` harness (instructions, permissions, slash commands,
subagents, hooks) and a sandboxed dev container, tuned for two goals:

- **Lower token usage** — a lean always-on `CLAUDE.md`, subagents that keep heavy
  reading out of the main context, and targeted-read conventions.
- **Readable for medium-skilled devs** — plain-language docs over cleverness, with
  every moving part explained in [`.claude/README.md`](.claude/README.md).

It is **language-agnostic**: nothing assumes Node. Commands detect the stack
(Node, Python, Rust, Go, Make) and permissions cover the common toolchains.

## What's inside

```
.claude/
├── CLAUDE.md          # Always-on project instructions (kept deliberately short)
├── README.md          # ★ Guide to the harness — read this first
├── settings.json      # Permissions (allow/deny) + the PreCompact hook
├── commands/          # Slash commands: /init /cleanup /status /pr /deploy …
├── agents/            # Subagents: explore (read-only search), review (diff review)
└── hooks/             # save-context.sh — runs automatically before compaction
.devcontainer/         # Sandboxed Docker env + network firewall
```

## Getting started

1. **Copy this repo** as the seed for your new project (or use it as a template).
2. Open it in the dev container (VS Code: "Reopen in Container") or your own env.
3. Run **`/init`** in Claude Code. It detects your stack and scaffolds
   `README.md`, `STATUS.md`, `CHANGELOG.md`, `.gitignore`, `.gitattributes`, and
   `_planning/`, and initializes git.
4. Start building. Use `/status` and `/update-status` to track work, `/cleanup`
   before commits, and `/pr` to open pull requests.

New to how any of this works? Read [`.claude/README.md`](.claude/README.md) — it
explains hooks, subagents, commands, and the state-file convention in plain terms.

## Conventions

- **`CLAUDE.md`** holds only stable instructions. Current work lives in
  `STATUS.md`, history in `CHANGELOG.md`, plans in `_planning/`.
- **Atomic, conventional commits** (`feat:`, `fix:`, `docs:`, …) so any change can
  be reverted cleanly.
- **Secrets never get committed** — `.env*`, `*.pem`, `*.key` are gitignored by
  `/init`.

## License

No license file is included yet — add one (`/init` can scaffold project files, or
drop a `LICENSE` in the root) before publishing.
