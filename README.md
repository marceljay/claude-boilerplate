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
├── settings.json      # Permissions (allow/deny), hooks (PreToolUse, SessionStart, PreCompact, SubagentStop), status line
├── commands/          # Slash commands: /init /cleanup /plans /pr /review /socratic …
├── agents/            # Subagents: explore-via-sonnet (search), review-diff, implement-scoped, docs-updater
├── skills/            # Auto-invoked skills: project-state upkeep (update-status, log, status, release), TDD, systematic-debugging, writing-plans, brainstorming, using-superpowers
├── scripts/           # usage-statusline.sh (status line), review_page.py (/review page), subagent_summary.py (tabulates the SubagentStop log)
└── hooks/             # PreToolUse: block_destructive.py (rm -rf/force-push variants), socket_scan.py (installs via Socket; opt-in), bounded_reads.py (no bare cat of big files) · SessionStart: first-run-check.sh, status-staleness-check.sh, plan-staleness-check.sh · PreCompact: save-context.sh · SubagentStop: log_subagent.py
.devcontainer/         # Sandboxed Docker env: Dockerfile, firewall script + allowed-domains.txt, shell shortcuts, STACKS.md (see below)
scripts/               # sync-harness.sh (install/refresh the harness in another repo), new-project.sh (detach a copy)
.npmrc                 # Supply-chain hardening: no install scripts, exact pins (see STACKS.md §Supply-chain hardening — incl. pnpm/cargo/go equivalents)
LICENSE                # MIT
```

**Bundled skills** (in `.claude/skills/`) work out of the box — Claude Code
auto-discovers any `.claude/skills/<name>/SKILL.md` at session start and Claude
invokes the matching one itself; there's nothing to install or call manually.
Four manage project state (`update-status`, `log`, `status`, `release`): they
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
2. **Open it in the dev container** (VS Code: "Reopen in Container"). The first
   open builds the image — a few minutes; it installs Claude Code and the
   tools listed under [Dev Container](#dev-container). Or use your own env and
   skip the container-specific steps.
3. **Start Claude** in the container terminal — `cc` (the shortcut; `cc-help`
   lists the others) or plain `claude`. The first run asks you to sign in
   (see [Signing in](#signing-in)). Then run **`/init`**. It offers to
   detach the boilerplate first (`scripts/new-project.sh` — renames this
   README to `BOILERPLATE.md`, deletes LICENSE, resets state files, drops the
   boilerplate's git history),
   then detects your stack and scaffolds `README.md`, `CHANGELOG.md`,
   `.gitignore`, `.gitattributes`, and `_planning/` (including
   `_planning/STATUS.md`, your living status + backlog — gitignored by default).
   Along the way it asks the per-project choices once: commit and testing
   policy, STATUS.md visibility, whether the shell shortcuts skip permission
   prompts, and — for a non-Node stack — walks you through
   [`STACKS.md`](.devcontainer/STACKS.md). Then add your project's own `LICENSE`.
4. **Rebuild the container once** ("Rebuild Container") if `/init` touched
   `.devcontainer/` — it renames the container and sets the shortcut flags in
   `devcontainer.json`, and a stack recipe edits the Dockerfile and firewall
   list. Those files are baked into the image, so nothing applies until you do.

### Path B — add the harness to an existing codebase

Don't copy the whole repo into an existing project — its README, LICENSE, and
git history would collide with yours. Instead, from a checkout of this repo **on
the host** (not inside a container; sibling directories aren't visible there):

```sh
scripts/sync-harness.sh ../your-project
```

When the target has no `.claude/` yet, the script runs in **install mode**:
after one confirmation it copies `.claude/` and `.devcontainer/` — and nothing
else — and asks for the dev container's name (default: the directory name).
Your `.git`, code, and README are never touched. (It also strips this
repo's recorded commit/testing policies from the copied `CLAUDE.md` so `/init`
asks you fresh.) Then reopen the project in its dev container, start Claude
(`cc` or `claude`) and run **`/init`**: it fills gaps without overwriting —
merges the required `.gitignore` entries into your existing one, scaffolds
`_planning/`, renames the container, records your policies, asks about the
shortcut flags, and flags non-Node stacks (the container ships Node-only;
recipes in [`.devcontainer/STACKS.md`](.devcontainer/STACKS.md)). Rebuild the
container once afterwards, as in Path A step 4.

Re-run the same command later to pull harness updates into the project
(**refresh mode**: mirrors commands/skills/agents/hooks and the firewall
script, confirms deletions, warns about hook files your kept `settings.json`
doesn't wire, splices the `Dockerfile` at its
`# ==== PROJECT LAYERS ====` marker so upstream fixes land while your stack
layers below it stay, and diff-asks before touching files that hold
per-project edits, such as `allowed-domains.txt` or `devcontainer.json` — with
a `u` answer that keeps yours and drops the boilerplate version beside it as
`<file>.upstream` for a hand merge). Overwriting `devcontainer.json` keeps
your container `"name"` and `CLAUDE_SHORTCUT_FLAGS`, and a copy that differs
only in those two counts as in sync, so they never get asked about again.

Already have a `.claude/` setup you want rid of — a hand-rolled harness, or
conventions worth abandoning? `scripts/sync-harness.sh --replace ../your-project`
backs the old `.claude/` + `.devcontainer/` up to a timestamped `tar.gz` at the
project root, then installs fresh. To replace just one file's conventions
(say, a sloppy `CLAUDE.md`), plain refresh mode is enough: answer `y` at that
file's diff prompt.

### Signing in

The first `claude` (or `cc`) in the container asks you to sign in. There's no
browser in the container, so it prints a URL: open it on your host, sign in
with your Claude subscription (Pro/Max/Team) or a Console account for
pay-per-token API billing, and paste the code back. Credentials live in the
`~/.claude` named volume, so they survive rebuilds and disappear only when the
volume does (Docker Desktop reset, `docker volume prune`, a container-ID
change) — then sign in again. `claude auth status` / `login` / `logout` manage
it from the shell, `/login` inside a session switches accounts. The firewall
allows the sign-in endpoints out of the box.

**API key instead of a sign-in.** Set `ANTHROPIC_API_KEY`. Put it in the
gitignored `.claude/settings.local.json` under `"env"` — the same place `/init`
puts the Socket token — never in `devcontainer.json` or any committed file. Or
pass a host variable through without storing it in the repo at all:
`"remoteEnv": { "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}" }` in
`devcontainer.json`. A key in the environment wins over a subscription
sign-in, so a stray key on the host silently moves you to pay-per-token;
`claude auth status` shows `apiKeySource` when that's happening.

**Other providers.** Claude Code can reach Anthropic's models through Amazon
Bedrock (`CLAUDE_CODE_USE_BEDROCK=1` + AWS credentials), Google Vertex AI
(`CLAUDE_CODE_USE_VERTEX=1` + gcloud credentials), or a compatible gateway
(`ANTHROPIC_BASE_URL`); setup per provider is in the
[Claude Code docs](https://code.claude.com/docs). Same rule for where the
variables go, plus one container-specific step: add the provider's **exact**
hostnames to [`.devcontainer/allowed-domains.txt`](.devcontainer/allowed-domains.txt)
and rebuild (no wildcards — e.g. `bedrock-runtime.eu-central-1.amazonaws.com`),
or the firewall drops every request and the tool just hangs.

### Then, either way

Start building. Work is tracked for you — the `update-status`/`log` skills
fire as items start and finish (`/status` any time for a summary). Use
`/cleanup` before commits, and `/pr` to open pull requests. Day to day in the
container: `ccc` picks up where the last session left off, `ccr` picks an
older one, and `ccw <name>` opens a session in its own git worktree for a
feature you want worked on in parallel (the full commands are in shell
history too — Ctrl-R "claude").

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
| `Dockerfile`        | Base image `node:22-bookworm` + dev tools (`git`, `gh`, `zsh`, `fzf`, `jq`, `delta`, `iptables`/`ipset`), downloads sha256-pinned. Installs Claude Code globally (autoupdater off — updates come with rebuilds) and runs as the non-root `node` user. Ends with a `# ==== PROJECT LAYERS ====` marker: your stack layers go below it and survive harness syncs. |
| `devcontainer.json` | Editor setup (ESLint, Prettier, GitLens, format-on-save), zsh as default shell, persistent zsh history + `~/.claude` config via named volumes, the `NET_ADMIN`/`NET_RAW` capabilities the firewall needs, and `CLAUDE_SHORTCUT_FLAGS` for the shell shortcuts. |
| `init-firewall.sh`  | A **default-deny network firewall**, run on container start. Pure logic; the domains come from the file below.                                                                                                 |
| `allowed-domains.txt` | The firewall allowlist, one domain per line. The per-project file: add your stack's hosts here.                                                                                                             |
| `claude-harness.zsh` | Shell shortcuts (`cc`, `ccc`, `ccr`, `ccw`, `cc-help`) and history seeding; the prompt shows a timestamp per command.                                                                                         |
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

- **Allowed:** GitHub (IP ranges pulled live from `api.github.com/meta`) plus
  whatever [`allowed-domains.txt`](.devcontainer/allowed-domains.txt) lists —
  out of the box the npm registry, `api.anthropic.com`, the VS Code
  marketplace, and telemetry endpoints (`sentry.io`, `statsig.com`) — plus
  DNS, SSH, localhost, and the host LAN.
- **Blocked:** everything else outbound is `REJECT`ed.
- **Self-verifying:** it confirms `example.com` is unreachable and `api.github.com`
  is reachable, and fails the startup if either check is wrong.

**Shell.** Every prompt carries a timestamp on the right (the moment the
previous command finished), handy for reading back a long session, and the
prompt uses plain-Unicode glyphs so it renders without a Nerd Font on the
host. The
container's zsh also defines `cc` (new session), `ccc` (continue the last
one), `ccr` (resume picker) and `ccw <name> [base]` (new session in a fresh
git worktree — with no base given it offers the default branch,
`dev`/`develop` if they exist, and the current branch), plus `cc-help`. All
of them append `CLAUDE_SHORTCUT_FLAGS`, set per project in
`devcontainer.json`'s `containerEnv` — typically the flag that skips
permission prompts, which is what the sandbox is for; leave it empty in a
project where you want the prompts. The full commands (flags included) are
seeded into the persisted shell history on the first shell of a fresh volume,
so Ctrl-R finds them. Plain `claude` never gets the flags, and none of this
exists on the host. Defined in
[`.devcontainer/claude-harness.zsh`](.devcontainer/claude-harness.zsh).

To allow another host, add its domain to
[`.devcontainer/allowed-domains.txt`](.devcontainer/allowed-domains.txt) and
**rebuild** (the list and the script are baked into the image; editing the repo
copy alone does nothing — deliberately, so the running container can't widen
its own egress). The script itself is harness logic and is mirrored by
`sync-harness.sh`; only the domain file is per-project. Adding a language stack? Use the tested
per-stack domain lists in [`.devcontainer/STACKS.md`](.devcontainer/STACKS.md) —
package managers usually need an index host *and* a separate download host, and
missing one makes installs hang silently. If a tool mysteriously can't reach
the network, the firewall allowlist is the first place to look.

## Conventions

- **Two CLAUDE.md files:** `.claude/CLAUDE.md` is the synced harness, the root
  `CLAUDE.md` is yours — its `## Harness settings` section records the
  per-project choices and any deviation from a harness rule, and wins on
  conflict. **`_planning/STATUS.md`** is the
  single living state file — In Progress + Needs input + Blockers (now) and a
  Backlog section (future, the only queue); **`CHANGELOG.md`** is the past. Items move between
  them, never copied. The backlog lives inside STATUS.md on purpose: it keeps the
  queue next to "In Progress" so the file doesn't go stale. STATUS.md is gitignored
  by default (private working state); `/init` asks whether to make it public.
- **Atomic, conventional commits** (`feat:`, `fix:`, `docs:`, …) so any change can
  be reverted cleanly.
- **Secrets never get committed** — `.env*`, `*.pem`, `*.key` are gitignored by
  `/init`.

## License

[MIT](LICENSE) — do whatever you like; no warranty.
