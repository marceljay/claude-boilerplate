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
  - [Run without VS Code (recommended)](#run-without-vs-code-recommended)
  - [The firewall (`init-firewall.sh`)](#the-firewall-init-firewallsh)
  - [Security model](#security-model)
- [Conventions](#conventions)
- [License](#license)

## What's inside

```
.claude/
├── CLAUDE.md          # Always-on harness instructions (synced; kept deliberately short)
├── CUSTOM.md          # Your per-project choices + deviations (never synced; wins on conflict)
├── README.md          # ★ Guide to the harness — read this first
├── settings.json      # Permissions (allow/deny), hooks (PreToolUse, SessionStart, PreCompact, SubagentStop), status line
├── commands/          # Slash commands: /init /cleanup /plans /pr /review /socratic …
├── agents/            # Subagents: explore-via-sonnet (search), review-diff, implement-scoped, docs-updater
├── skills/            # Auto-invoked skills: project-state upkeep (update-status, log, status, release), TDD, systematic-debugging, writing-plans, brainstorming, using-superpowers
├── scripts/           # usage-statusline.sh (status line), review_page.py (/review page), changelog_fold.py (folds changelog.d/ fragments), subagent_summary.py (tabulates the SubagentStop log)
└── hooks/             # PreToolUse: block_destructive.py (rm -rf/force-push variants), socket_scan.py (installs via Socket; opt-in), bounded_reads.py (no bare cat of big files) · SessionStart: first-run-check.sh, status-staleness-check.sh, plan-staleness-check.sh · PreCompact: save-context.sh · SubagentStop: log_subagent.py
.devcontainer/         # Sandboxed Docker env: Dockerfile, firewall script + allowed-domains.txt, shell shortcuts, agent-ports, STACKS.md (see below)
scripts/               # sync-harness.sh (install/refresh the harness in another repo; --install-shell installs agent.zsh), agent.zsh (run the container from the host without VS Code), new-project.sh (detach a copy), tests/
changelog.d/           # One changelog fragment per change, written on branches; folded into CHANGELOG.md on the release branch
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
2. **Open it in the dev container** — either `agent` from a host terminal
   ([Run without VS Code](#run-without-vs-code-recommended), the more
   isolated path) or VS Code's "Reopen in Container". The first start builds
   the image — a few minutes; it installs Claude Code and the tools listed
   under [Dev Container](#dev-container). Or use your own env and skip the
   container-specific steps.
3. **Start Claude** in the container terminal — `cc` (the shortcut; `cc-help`
   lists the others) or plain `claude`. The first run asks you to sign in
   (see [Signing in](#signing-in)). Then run **`/init`** (under `agent.zsh`:
   in a one-time `agent --setup` container, since `/init` edits
   `.devcontainer/` and `.git`, which the normal container mounts
   read-only). It offers to
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
4. **Rebuild the container once** (`agent-rebuild`, or VS Code's "Rebuild
   Container") if `/init` touched `.devcontainer/` — it renames the
   container and sets the shortcut flags in `devcontainer.json`, and a stack
   recipe edits the Dockerfile and firewall list. Those files are baked into
   the image, so nothing applies until you do. Review `git diff --
   .devcontainer` first: the rebuild runs whatever is in there.

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
| `agent-ports`       | Container ports `scripts/agent.zsh` publishes on the host (loopback only, ephemeral host port). Per-project; empty by default. Ignored by the VS Code path, which auto-forwards.                               |
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

### Run without VS Code (recommended)

VS Code's "Reopen in Container" is convenient, but the Dev Containers
extension opens channels from the container back to your machine (listed
under [Security model](#security-model)). `scripts/agent.zsh` starts the
same image with plain Docker from a host terminal and nothing else: the
project folder, two named volumes, two capabilities. Inside, Claude runs in
`tmux`, so a closed terminal tab doesn't end the session.

**Install** (host, once; macOS or Linux, with Docker and zsh — bash users
get a shim, see the Linux notes below):

```sh
scripts/sync-harness.sh --install-shell
```

It copies `scripts/agent.zsh` to `~/.config/zsh/agent.zsh` (a plain file,
mode 0644, never a symlink — the file decides what the container sees, so it
must live where no agent can write) and offers the one `source` line for
`~/.zshrc`. Re-running shows a diff and backs the old copy up before
replacing it. A normal `sync-harness.sh <target>` offers the same step at
the end. The file is not copied into projects.

**Daily use** — from the project folder, or with the folder as argument:

| Command | What it does |
| --- | --- |
| `agent` | Builds the image if missing, creates the container if missing, starts it if stopped, applies the firewall if the OUTPUT policy isn't DROP, attaches to tmux. Idempotent; `Ctrl-b d` detaches, the session keeps running. |
| `agent --no-tmux` / `agent-shell` | Same, but a plain zsh (closing the tab ends what runs in it). |
| `agent --setup` / `agent-setup` | One-time container for `/init` and `scripts/new-project.sh`: no read-only overlays, permission prompts on. Plain `agent` refuses to attach to it until you `agent-rebuild`. |
| `agent-rebuild` | `docker build --pull --no-cache` (fresh base image, newest Claude Code), new container. When `.devcontainer` differs from what the current image was built from (uncommitted or committed), it lists the changes and asks first. |
| `agent-recreate` | New container from the existing image — after changing `agent-ports`, the shortcut flags, or `.git/config` on the host. Same review prompt as `agent-rebuild`. |
| `agent-stop` | Stops the container; sign-in, memory and history live in volumes and survive. |
| `agent-ports` | Host ports published for the container (`docker port`). |

Names are `claude-<folder>` (lowercased, odd characters → `-`); containers
you created by hand under that name are picked up as they are. Two projects
with the same folder name share the name: `agent` refuses to attach when the
existing container mounts the other folder. The
container's time zone comes from `AGENT_TZ` (default `$TZ`, else
Europe/Berlin); set it in `~/.zshrc` before the `source` line.

**What's different inside.** `.devcontainer/`, `.git/hooks/` and
`.git/config` are **read-only** (and `.git` itself is a mount point, so it
can't be renamed away and replaced by a writable copy): an agent can't
change what the next rebuild runs, what git runs on your machine
(`core.hooksPath`, `core.fsmonitor`, filter drivers), or where `git push`
goes. Consequences: `/pr` pushes with `git
push origin HEAD` (no `-u`), `ccw` creates worktrees with `--no-track`, and
`/init` either runs in `agent --setup` or prints the `.devcontainer` edits
for you to apply on the host. Git rewrites `.git/config` by renaming a new
file over it, so after a host-side `git remote add` or `git config` the
container still sees the old content until `agent-recreate`. There is no
`$BROWSER`: `/dev` prints the container port and the `docker port` command
that shows the host side. Ports are only published if listed in
[`.devcontainer/agent-ports`](.devcontainer/agent-ports) (one per line,
loopback, ephemeral host port — several projects never collide). Git author
and committer come from your host's global git config as environment
variables, which win over a per-repo `user.email`.

**Drift warning.** The image is labelled with a hash of `.devcontainer/` at
build time. When `agent` finds the directory changed since then, it warns
(`.devcontainer changed since the last build — review git diff --
.devcontainer, then agent-rebuild`) and still attaches: changes there only
take effect at a rebuild, which is exactly when they must have been reviewed.

**What you give up versus VS Code:** the editor attached to the container
(use VS Code on the host folder instead; it is the same files), automatic
port forwarding (use `agent-ports`), `$BROWSER`, the marketplace extensions,
and `.gitconfig` beyond name and email. You can still "Reopen in Container"
later — nothing here removes that path, it is just the less isolated one.

**Host notes.** The harness runs on macOS and Linux hosts (and on Windows
through WSL for the VS Code path). The boundary is the same; what sits
around it differs.

*Linux:*

- **File ownership.** Native Docker Engine shows the repo inside the
  container with your host uid, and the container user is uid 1000. `agent`
  builds the image with your uid and gid (`USER_UID`/`USER_GID` build args)
  and warns when an existing image was built for another uid; the VS Code
  path does the same through `updateRemoteUserUID`. If `agent` says the
  image was built for another uid, run `agent-rebuild`.
- **No VM in between.** On macOS the container runs inside Docker Desktop's
  VM; on Linux it shares your kernel. A privilege escalation inside the
  container is a host compromise, so the `no-new-privileges` and
  user-namespace items in `docs/SECURITY-MODEL.md` matter more here.
- **The gateway is your machine.** The Docker bridge gateway
  (`172.17.0.1`) is the host itself, so services listening on `0.0.0.0` on
  the host are reachable there. Inbound from that network is allowed for
  published ports; `# allow-host-network` would expose the host's own
  listeners and is best left off on Linux.
- **Bash as login shell.** `agent.zsh` is zsh. `--install-shell` detects a
  bash `$SHELL` and offers a block for `~/.bashrc` that runs the functions
  through `zsh -c`; zsh must be installed. `export AGENT_TZ=…` in `.bashrc`
  if you want a time zone other than `$TZ`.
- **`docker` group membership is root on the host.** Anyone (or anything)
  that can talk to the Docker socket can start a privileged container. Keep
  the socket off the container (it is) and your own account's membership in
  mind.
- Terminal and clipboard: GNOME Terminal, kitty, alacritty and others handle
  OSC 52 differently; check your terminal's clipboard-write setting. The
  secret-service credential helper is the keychain equivalent that a VS Code
  attach would proxy.

*macOS:*

- Use **iTerm2 3.6.10 or later** (CVE-2026-41253 is fixed there). Don't use
  iTerm2's `tmux -CC` integration for agent sessions: that path has had
  several code-execution CVEs, and the point of tmux here is a plain
  scrollback. The container's `/etc/tmux.conf` turns off `set-clipboard`
  and `allow-passthrough` so a command inside can't write your clipboard or
  relay raw escape sequences to your terminal — any pane can `tmux set`
  them back, so treat them as a default, not a boundary.
- In iTerm2 → Profiles → Terminal, turn **off** "Terminal may report window
  title" (and similar "report …" options): a process in the container sets
  the title, and a terminal that echoes it back hands text to the shell.
- Docker Desktop's socket lives inside Docker Desktop's app container. The
  first `docker` command from a terminal app may trigger macOS's
  "<terminal> would like to access data from other apps" prompt. Allowing
  it lets that terminal app talk to Docker Desktop's files (the socket);
  it grants nothing to the container.

### The firewall (`init-firewall.sh`)

On every container start (and on `agent` whenever the OUTPUT policy isn't
DROP) the container locks outbound traffic down to a small allowlist, so
commands Claude runs can't reach arbitrary hosts:

- **Allowed:** GitHub (IP ranges pulled live from `api.github.com/meta`, any
  port — so `git@github.com` SSH works) plus whatever
  [`allowed-domains.txt`](.devcontainer/allowed-domains.txt) lists — out of
  the box the npm registry, `api.anthropic.com`, `platform.claude.com`
  (sign-in) and the VS Code marketplace — plus DNS **to the configured
  resolvers only**, localhost, and inbound from the Docker gateway network
  (that is how published ports arrive). Outbound to that network is off
  unless `allowed-domains.txt` carries the `# allow-host-network` directive
  (sibling service containers).
- **Blocked:** everything else outbound is `REJECT`ed; all IPv6 egress is
  blocked; there is no blanket SSH or DNS any more.
- **Re-runnable:** `sudo /usr/local/bin/init-firewall.sh` on a live container
  resolves everything first, builds the new ipset beside the old one, swaps
  it, and replaces the filter table in one `iptables-restore`. Docker's own
  DNS NAT rules are never touched.
- **Self-verifying:** `example.com` unreachable, `api.github.com` reachable,
  DNS still resolves, TCP 22 to a non-GitHub address blocked, DNS to a
  foreign resolver blocked, IPv6 egress blocked where IPv6 exists. Any
  failure fails the start (VS Code waits for it; `agent` stops the container).

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

### Security model

The full threat model — fourteen scenarios with vector, gain, mitigation,
residual risk and a check for each, plus the control matrix for both
container paths — is in [`docs/SECURITY-MODEL.md`](docs/SECURITY-MODEL.md).
The short version:

The container is the boundary: Claude Code often runs in it with permission
prompts skipped (`CLAUDE_SHORTCUT_FLAGS`), so what matters is which paths
lead from the container back to your machine or out to the internet. Know
these before trusting the sandbox:

- **VS Code attach opens host channels.** The Dev Containers extension
  forwards your SSH agent (`SSH_AUTH_SOCK`), copies `~/.gitconfig` in,
  installs a git credential helper backed by the host keychain, exposes a
  `code` CLI socket and a remote-containers IPC socket that can run
  extension commands on the host, and sets `$BROWSER` to `code
  --openExternal`, which opens any URL in your browser — past the firewall.
  Blanking those variables (the commented `remoteEnv` block in
  `devcontainer.json`) only hides them; the host still answers on the
  sockets. `scripts/agent.zsh` opens none of them.
- **The workspace is a read-write bind mount of your repo.** Anything the
  agent writes there is on your disk. Three places are executed by your
  machine, not the container: `.devcontainer/*` (the next rebuild runs it;
  `initializeCommand` runs on the host), `.git/hooks/*` and `.git/config`
  (`core.hooksPath`, `core.fsmonitor`, filter drivers, `core.sshCommand`
  — run by every git command you type on the host). `agent.zsh` mounts
  those three read-only; the VS Code path does not. Either way, review
  `git diff -- .devcontainer` before a rebuild.
- **Firewall limits.** GitHub is allowed by IP range, so an injected prompt
  can push to any GitHub repository with a token it brought along — the
  allowlist bounds hosts, not repositories. DNS reaches only the configured
  resolvers, but a recursive resolver still answers for any name, so DNS
  tunneling is narrowed, not closed; a filtering resolver that answers only
  allowlisted names is the planned follow-up. Allowlisted hosts are
  resolved once at start; a CDN that moves IPs later makes a tool fail until
  the firewall is re-run.
- **Telemetry is off, not just unlisted.** `DISABLE_ERROR_REPORTING=1` and
  `DISABLE_TELEMETRY=1` are set in both paths; `sentry.io` and `statsig.com`
  are gone from the allowlist because anyone can post to them with their
  own key. Side effect per the Claude Code docs: no feature-flag evaluation,
  so Remote Control is unavailable in the container.
- **The permission allowlist in `.claude/settings.json` is broad** (`node`,
  `npx`, `python`, `curl`, `gh`, `WebFetch`, …), so prompts restrict little
  even when they are on; the firewall and the mounts do the real work.

## Conventions

- **`.claude/CLAUDE.md` is the synced harness; `.claude/CUSTOM.md` is yours** —
  it records the per-project choices and any deviation from a harness rule,
  is imported by CLAUDE.md, never synced, and wins on conflict. **`_planning/STATUS.md`** is the
  single living state file — In Progress + Needs input + Blockers (now) and a
  Backlog section (future, the only queue); **`CHANGELOG.md`** is the past — written on branches as one
  `changelog.d/` fragment per change and folded in on the release branch, so
  parallel agents never conflict on it. Items move between
  them, never copied. The backlog lives inside STATUS.md on purpose: it keeps the
  queue next to "In Progress" so the file doesn't go stale. STATUS.md is gitignored
  by default (private working state); `/init` asks whether to make it public.
- **Atomic, conventional commits** (`feat:`, `fix:`, `docs:`, …) so any change can
  be reverted cleanly.
- **Secrets never get committed** — `.env*`, `*.pem`, `*.key` are gitignored by
  `/init`.

## License

[MIT](LICENSE) — do whatever you like; no warranty.
