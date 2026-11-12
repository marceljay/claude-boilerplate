# Harness security model

Threat model for the dev container this boilerplate ships: what a rogue or
prompt-injected agent inside it could reach, what stops it today, and what
does not. Last reviewed 2026-11-13, against commit `70ad075` and later.

The README's [Security model](../README.md#security-model) section is the
short version. This document is the long one: every channel, every
scenario, the residual risk, and how to check each control by hand.

## Scope and trust assumptions

The container is the security boundary. Claude Code runs inside it, usually
with permission prompts off (`CLAUDE_SHORTCUT_FLAGS`), so every command the
model chooses to run executes with no human in the loop. The model must be
assumed hostile at any moment: a prompt injection in a README, a web page, a
package description or a GitHub issue is enough to turn it. The question
this document answers is what a hostile process inside the container can
reach, and what stops it.

**Trusted:** the macOS host and its user, Docker Desktop and the Linux
kernel it runs, the image build inputs after a human has reviewed
`git diff -- .devcontainer`, the host-side `agent.zsh` copy in
`~/.config/zsh`, and the terminal application.

**Not trusted:** anything that runs as the `node` user inside the container
(Claude Code, every tool it calls, every package it installs, every dev
server it starts), the contents of the repository after the agent has
touched them, and anything fetched over the allowed egress.

**Two ways the container starts, with different boundaries:**

| | `agent` (plain Docker, `scripts/agent.zsh`) | VS Code "Reopen in Container" |
| --- | --- | --- |
| Host paths mounted | project folder only | project folder only |
| `.devcontainer`, `.git/hooks`, `.git/config` | read-only, `.git` is a mount point | writable |
| Host channels (SSH agent, keychain, `code` IPC, `$BROWSER`) | none | all open |
| `.gitconfig` | name and email as env vars | whole file copied in |
| `initializeCommand` from `devcontainer.json` | never read | runs on the host at every reopen |
| Ports | only those in `agent-ports`, loopback | auto-forwarded |

The rest of this document treats the `agent` path as the baseline and names
where the VS Code path is weaker. Residual risks that neither path closes
are listed as such.

## Assets at risk

Five things are worth protecting, in descending order of damage if lost.

| Asset | Where it lives | Loss looks like |
| --- | --- | --- |
| Host machine: files, keychain, SSH keys, other repos | outside the container | any code execution on the host, or a channel that signs or authenticates with host credentials |
| Repository integrity | the bind-mounted `/workspace`, pushed to GitHub | a backdoored commit, a hook or config that runs on the host, a rewritten `.devcontainer` that the next rebuild bakes in |
| Secrets the container holds | `~/.claude` volume (OAuth token), `.claude/settings.local.json` (API keys, Socket token), `.env` files, GitHub token from `gh auth` | exfiltration over any allowed egress, or abuse of the Anthropic account and GitHub access from inside |
| Confidentiality of the code and conversation | `/workspace`, the model context | exfiltration to a host the agent can reach: any GitHub repository, a DNS tunnel, the allowlisted APIs |
| Other containers and services on the host | the Docker bridge network, published ports | lateral movement to sibling service containers; a malicious page served to the host browser via a published dev server |

Two things are explicitly **not** protected and are accepted: the
repository's working tree is writable by design (the agent's job is to edit
it), and prompts plus file contents go to `api.anthropic.com` by design.
Review before commit, and the data-usage terms of the account, are the
controls there.

## Attack surface map

Everything the agent can do to the host goes through five channels between
the container and the host; everything it can send out goes through the
firewall. The `agent` path keeps only the first two host channels open, with
read-only guards on the mount; the VS Code path opens all five and copies
`.gitconfig` in. Supply chain runs the other way: code that arrives through
it executes with the agent's reach, and, for VS Code extensions, partly on
the host.

```
 macOS host                                              Container (node user)
 ┌──────────────────────────┐                          ┌──────────────────────────┐
 │ Terminal + tmux client   │── docker exec … tmux ───▶│ Claude Code + tools      │
 │ Docker Desktop           │◀── bind mount (rw) ─────▶│ /workspace (the repo)    │
 │ VS Code (optional)       │◀══ SSH agent, keychain, ═│ Firewall (root via sudo) │
 │ Keychain, SSH agent,     │    code IPC, $BROWSER    │ ~/.claude volume (token) │
 │   browser                │◀── published ports ──────│ Dev servers, tmux        │
 │ Host git, direnv, tasks  │◀── escape sequences ─────│                          │
 │   (execute repo files)   │                          └────────────┬─────────────┘
 └──────────┬───────────────┘                            egress:    │   ▲ supply chain:
   extensions │ (marketplace code                     ipset only,   │   │ base image, apt,
   run here too)                                      REJECT rest   ▼   │ npm, extensions
 ┌─────────────────────────────────────────────────────────────────────────────────┐
 │ Internet, as the firewall sees it                                               │
 │  GitHub (all ranges) · api.anthropic.com · registry.npmjs.org · DNS resolvers  │
 │  any repo, any port    + platform.claude.com  + VS Code marketplace  recursive  │
 └─────────────────────────────────────────────────────────────────────────────────┘
```

Double line: open only on the VS Code path. On the `agent` path the bind
mount carries read-only overlays for `.devcontainer`, `.git/hooks` and
`.git/config`. GitHub and the resolvers are the residual exfiltration paths.

## Threat scenarios

Each scenario names the vector, what an attacker gains, what stops it today,
what remains, and how to check. "Agent path" means a container started by
`scripts/agent.zsh`; "VS Code path" means "Reopen in Container".

### 1. Widening the firewall by editing the allowlist or the script

**Vector.** The agent edits `.devcontainer/allowed-domains.txt` or
`init-firewall.sh` to add an exfiltration host, then waits for a rebuild.

**Gain.** Permanent egress to a host of its choice from the next image on.

**Mitigation.** The running firewall reads only the copies baked into the
image (`/etc/init-firewall/allowed-domains.txt`,
`/usr/local/bin/init-firewall.sh`), so an edit changes nothing until a human
rebuilds. On the agent path `.devcontainer` is a read-only mount, so the edit
is impossible; the image carries a sha256 label of `.devcontainer` and
`agent` warns on drift; `agent-rebuild` and `agent-recreate` list the changes
and ask.

**Residual.** On the VS Code path the directory is writable and "Rebuild
Container" asks nothing. In `agent --setup` it is writable by design. A
committed edit leaves `git status` clean, so the hash gate, not git, is the
real check. Humans skimming a diff miss single-line changes to a domain list.

**Verify.** `touch .devcontainer/x` inside the container fails with
"Read-only file system"; edit a file on the host and run `agent`: the
warning appears.

### 2. Disabling or bypassing the firewall from inside

**Vector.** `iptables -F`, `ipset flush`, or a re-run of the script with a
modified allowlist.

**Gain.** Unrestricted egress for the rest of the session.

**Mitigation.** Rule changes need root. The `node` user has `sudo` for
exactly one command, `/usr/local/bin/init-firewall.sh`, root-owned and 0755,
which reads only baked files. The capabilities `NET_ADMIN`/`NET_RAW` belong
to the container, not the user; without root they grant nothing. Rules are
lost on restart, but `agent` checks the OUTPUT policy before every attach and
re-applies them.

**Residual.** Any local privilege escalation inside the container (kernel,
sudo, setuid binary from a package) ends the firewall. The container runs as
a plain user with the default seccomp profile but no user-namespace remapping
and no `no-new-privileges`. A restart by hand (`docker start`) followed by
`docker exec` outside `agent` gives a shell with no rules until `agent` runs.

**Verify.** `iptables -S` as `node` fails with "Permission denied"; `sudo -l`
lists only the script.

### 3. `.git/config` and `.git/hooks`: making the host's git run attacker code

**Vector.** Write `core.hooksPath`, `core.fsmonitor`, `core.sshCommand`, a
`[filter]` driver, an `[include]`, or a `pre-commit` hook. Every `git`
command the human later types on the host executes it, as the human, outside
any sandbox.

**Gain.** Code execution on the macOS host with the user's full rights,
triggered by `git status`.

**Mitigation.** Agent path: `.git/hooks` and `.git/config` are read-only
mounts, and `.git` itself is a mount point so it cannot be renamed and
replaced by a writable copy. `/pr` pushes without `-u`, `ccw` uses
`--no-track`, so nothing in the harness needs to write them.

**Residual.** VS Code path: fully writable. Both paths: other files the host
executes from the repo are writable by design: `.vscode/tasks.json` with
`runOn: folderOpen`, `.vscode/settings.json` keys that name binaries,
`.envrc` for direnv, `Makefile`, `package.json` scripts, a committed
`.githooks/` that a README tells the user to enable. VS Code's Workspace
Trust and direnv's allow step are the only gates, and both are one click. A
host-side `git config` write after the container started is invisible inside
until `agent-recreate` (the mount holds the old inode).

**Verify.** Inside: `git config x.y z` fails, `mv .git .git.x` fails with
"Device or resource busy". On the host: `git status` in the repo runs nothing
unexpected (check
`git config --show-origin --list | grep -E 'hooksPath|fsmonitor|sshCommand|filter'`).

### 4. `devcontainer.json`: `initializeCommand` runs on the host

**Vector.** The Dev Containers extension runs `initializeCommand` on the host
before the container starts, and `onCreateCommand`, `postCreateCommand`,
`postStartCommand` inside it. An agent that can write `devcontainer.json`
adds a host command that runs at the next reopen. `runArgs` can add
`--privileged`, a Docker socket mount, or `--network host`; `mounts` can
bind `~/.ssh`; `remoteEnv` can inject variables.

**Gain.** Host code execution, or a container with no boundary at all, both
from one JSON edit.

**Mitigation.** Agent path: `agent.zsh` never reads `devcontainer.json`
except two single-line values (`CLAUDE_SHORTCUT_FLAGS`, validated against
`^(--[a-z0-9-]+( |$))*$`, and `CLAUDE_CODE_VERSION`, validated as a version
string), and the file is read-only. The container's options are fixed in
`agent.zsh`, which lives outside the repo.

**Residual.** VS Code path: this is the largest single hole. Review
`git diff -- .devcontainer` before every rebuild; the extension does not
warn. The agent could also write `.devcontainer.json` at the repo root; VS
Code prefers `.devcontainer/devcontainer.json` when both exist, but an edited
`.vscode/settings.json` can point at another config.

**Verify.** `grep -n initializeCommand .devcontainer/devcontainer.json` on
the host shows nothing;
`docker inspect <container> --format '{{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}} {{json .Mounts}}'`
shows `false bridge` and only the project mounts and two volumes.

### 5. VS Code sockets and `$BROWSER`

**Vector.** On the VS Code path the container holds `SSH_AUTH_SOCK` (host
agent forwarded), `VSCODE_IPC_HOOK_CLI` (the `code` CLI socket),
`REMOTE_CONTAINERS_IPC` (extension-host IPC that can run extension commands
on the host), `GIT_ASKPASS` (host keychain helper), and `$BROWSER` set to
`code --openExternal`.

**Gain.** Sign and authenticate as the user with keys that never leave the
host (push anywhere, SSH anywhere the key opens). Open any URL in the host
browser, past the firewall: exfiltration in a query string, phishing,
`file://` or custom URL schemes that launch host applications. Run
`code --command` and extension commands on the host.

**Mitigation.** Agent path: none of these exist; the probe is
`env | grep -E 'SSH_AUTH_SOCK|VSCODE_IPC|REMOTE_CONTAINERS|GIT_ASKPASS|BROWSER'`
returning nothing.

**Residual.** VS Code path: blanking the variables through `remoteEnv` only
hides them from processes that honour the environment. The sockets still
exist under `/tmp` and `/root/.vscode-server`, and the host still answers on
them; a process can find them with `find / -type s`. Treat the VS Code path
as "the agent can use my SSH agent and open URLs on my Mac".

**Verify.** On the agent path the `env` probe is empty and
`find / -type s 2>/dev/null` lists only Docker's own and tmux's sockets.

### 6. Copied `.gitconfig` and credential helpers

**Vector.** VS Code copies the host `~/.gitconfig` into the container. A
`credential.helper = osxkeychain` line does not work in Linux, but the
extension installs its own helper that proxies to the host keychain.
`git credential fill` then returns the user's GitHub token to anything in the
container.

**Gain.** The user's GitHub identity: push to any repo they can write to,
read private repos, through the allowed GitHub egress.

**Mitigation.** Agent path: only `user.name` and `user.email` are passed, as
environment variables. No helper, no `.gitconfig`. GitHub access inside comes
only from what the user signs in to deliberately (`gh auth login`), and that
token is the agent's to use, which is by design for `/pr`.

**Residual.** `gh auth` tokens and the Claude OAuth token in the `~/.claude`
volume are readable by the agent; see scenario 13. Env-var identity
overrides a per-repo `user.email`.

**Verify.** Inside: `git config --show-origin credential.helper` prints
nothing; `cat ~/.gitconfig` fails.

### 7. Published ports and dev servers

**Vector.** A dev server the agent starts is reachable from the host browser
(auto-forwarded by VS Code, or listed in `agent-ports`). The agent controls
every byte it serves. Inside the bridge network the server binds `0.0.0.0`,
so sibling containers reach it too.

**Gain.** A malicious page in the user's browser: JavaScript on
`localhost:<port>` can probe other local services (CSRF to anything without
auth on loopback), prompt for credentials under a trusted-looking origin, or
exploit a browser bug.

**Mitigation.** Agent path publishes only ports named in `agent-ports`, on
`127.0.0.1`, with an ephemeral host port; the file is under the read-only
mount, so the agent cannot add ports. Nothing is published by default.
Inbound to the container is limited to the gateway network.

**Residual.** The user opens the URL in their everyday browser with their
everyday sessions. VS Code forwards any port the container opens, with a
notification but no decision. This is inherent to running a dev server you
did not write; the control is to treat the page as untrusted content.

**Verify.** `docker port <container>` lists only the intended ports, all on
`127.0.0.1`.

### 8. Terminal and clipboard escape sequences

**Vector.** Output from the container is rendered by the host terminal. OSC
52 writes the host clipboard; title-setting sequences plus "report title"
answer-backs inject text into the shell input; terminal emulators have had
code-execution bugs in escape-sequence parsing (iTerm2 CVE-2026-41253;
several in the `tmux -CC` control-mode path).

**Gain.** Paste a prepared command into the user's clipboard, inject
keystrokes, or exploit the terminal.

**Mitigation.** `/etc/tmux.conf` sets `set-clipboard off` and
`allow-passthrough off`, so tmux does not forward OSC 52 or raw passthrough
sequences. README asks for iTerm2 3.6.10 or later, no `tmux -CC`, and
"Terminal may report window title" off.

**Residual.** Any pane can run `tmux set -g set-clipboard on`; the config is
a default, not an enforcement. `agent --no-tmux` and `docker exec` shells
bypass tmux entirely. The terminal's own parser is the trust boundary and is
outside this repo.

**Verify.** Inside tmux: `tmux show -g set-clipboard` prints `off`.

### 9. Exfiltration through allowed egress

**Vector.** Even with the firewall intact, the agent can send data to
anything on the allowlist.

**Gain.** Code, secrets, or conversation contents leave the machine.

**Channels that remain open, in order of capacity:**

| Channel | Why it works | Capacity |
| --- | --- | --- |
| Any GitHub repository | the ipset holds GitHub's IP ranges; an injected prompt can carry its own token and `git push` to an attacker's repo, or open an issue with `gh` | unlimited |
| DNS | queries go to the configured resolver, which is recursive and resolves any name; data rides in query names (`<base32>.attacker.example`) | tens of bytes per query, thousands of queries per minute |
| `api.anthropic.com` | prompts and tool output go there by design | by design; governed by account data terms |
| `registry.npmjs.org` | `npm publish` with a token the agent holds | needs a token |
| Allowlisted project APIs | anything added for the stack with an authenticated write path | per service |

**Mitigation.** Closed since this review: TCP 22 anywhere, UDP 53 anywhere,
the host /24, `sentry.io`, `statsig.com`, all IPv6.

**Residual.** The first two rows. The proposed controls are a filtering
resolver that answers only allowlisted names (closes DNS tunnelling) and an
egress proxy that restricts GitHub to this project's repositories (closes the
GitHub row). Neither exists yet.

**Verify.** `dig +short @1.1.1.1 example.com` returns nothing;
`dig +short example.com` returns an address (resolver works, so the tunnel
is narrowed, not closed).

### 10. Packages executed inside the container

**Vector.** `npm install` of a malicious or typosquatted package; `npx`
running arbitrary code; a `postinstall` script; a dependency's code at test
time.

**Gain.** The agent's reach, nothing more: the package runs as `node` inside
the same boundary. It cannot do anything the agent itself could not.

**Mitigation.** `.npmrc` sets `ignore-scripts=true` and exact pins;
lockfiles; the optional Socket scan hook. The firewall limits what the
package can call home to. Supply-chain hardening recipes per stack in
`STACKS.md`.

**Residual.** `ignore-scripts` stops install-time execution only;
`node_modules` code runs at `require` time regardless. A package can read the
same secrets the agent can (scenario 13). On the host, if the user runs
`npm install` or `npm test` in the same checkout outside the container, the
package runs on the host with the user's rights.

**Verify.** `npm config get ignore-scripts` prints `true` inside the
container.

### 11. VS Code extensions

**Vector.** `devcontainer.json` lists extensions that the Dev Containers
extension installs automatically into the container's extension host. Some
extensions, and all UI extensions, run on the host. A malicious or
compromised extension (marketplace takeover, maintainer account compromise)
has at least the agent's reach plus the VS Code channels of scenario 5, and
on the host side the user's rights.

**Gain.** Host code execution through the extension host, or the full
scenario-5 channel set without even needing the agent.

**Mitigation.** The list is four well-known publishers (`anthropic`,
`dbaeumer`, `esbenp`, `eamodio`). Marketplace hosts are on the firewall
allowlist only for this path. The agent path installs no extensions and does
not contact the marketplace.

**Residual.** An agent on the VS Code path can edit the extensions list; the
next reopen installs its choice. `.vscode/extensions.json` recommendations
prompt the user on the host. Extension auto-update is a persistent
supply-chain exposure independent of this harness.

**Verify.** `code --list-extensions` in the container matches the four
listed; on the agent path the command does not exist.

### 12. Image build inputs

**Vector.** The image pulls `node:22-bookworm` by tag, Debian packages,
`npm@latest`, `@anthropic-ai/claude-code@latest`, and two sha256-pinned
downloads (git-delta, zsh-in-docker). A compromised upstream enters the image
at rebuild.

**Gain.** Code in the image runs as `node` (or root during build) inside the
container; a compromised Claude Code binary would hold the OAuth token and
act as the agent.

**Mitigation.** Two downloads are hash-pinned and fail the build on
mismatch. `agent-rebuild` uses `--pull --no-cache` so the inputs are the
current upstream, not a stale layer. The build fails on `claude --version`
if the install is broken.

**Residual.** The base image and Claude Code are not digest-pinned; `latest`
is a trust-the-publisher decision made at each rebuild. The build itself
runs on Docker Desktop with network access and could be the first point
where an attacker-controlled registry answers.

**Verify.**
`docker image inspect <image> --format '{{index .Config.Labels "agent.devcontainer-sha256"}}'`
matches the hash of the reviewed `.devcontainer`; pin `CLAUDE_CODE_VERSION`
in `devcontainer.json` if reproducibility matters.

### 13. Credentials stored in the config volume and the repo

**Vector.** The `~/.claude` volume holds the OAuth token (and memory, which
can carry anything the agent chose to remember). `.claude/settings.local.json`
may hold `ANTHROPIC_API_KEY` or `SOCKET_CLI_API_TOKEN`. `gh auth` stores a
GitHub token. `.env` files hold project secrets.

**Gain.** The agent reads its own credentials and sends them out through
scenario 9; an attacker then uses the Anthropic account or GitHub access
from elsewhere.

**Mitigation.** The firewall limits where they can be sent. `.env*` and
`settings.local.json` are gitignored, so they do not leak through a commit.
The volume is per project name, not shared across projects.

**Residual.** Inherent: a process that must authenticate holds the
credential. Scope tokens narrowly (GitHub fine-grained token for this
repository only; a Console API key with a spend limit rather than a
subscription OAuth token where exfiltration risk matters). Rotate after any
suspected injection.

**Verify.** `gh auth status` shows a token scoped to what the project needs;
no `.env` is tracked (`git ls-files | grep -i env`).

### 14. Host-side harness files

**Vector.** `~/.config/zsh/agent.zsh` decides what the container sees. If it
were a symlink into a repo, or lived in a dotfiles repo the agent can edit,
the next `agent` would run attacker code on the host. `scripts/sync-harness.sh`
runs on the host and copies files from the boilerplate checkout into other
projects. `.claude/hooks/*.py` and `settings.json` hooks run wherever Claude
Code runs: in the container normally, but on the host if someone starts
`claude` there.

**Gain.** Host code execution at the next `agent` or the next Claude session
on the host.

**Mitigation.** `--install-shell` refuses a symlinked file or directory,
copies with `install -m 0644`, shows a diff before replacing, prints the
version and SHA-256. The header tells the user to keep it outside any
agent-writable folder. Claude Code's workspace trust gates project hooks on
first open.

**Residual.** Running `sync-harness.sh` from a boilerplate checkout an agent
has modified propagates that modification; review the boilerplate's own diff
first. Running Claude on the host at all removes every control in this
document except the deny list and `block_destructive.py`.

**Verify.** `ls -l ~/.config/zsh/agent.zsh` shows a regular file, mode 0644;
`shasum -a 256` of it matches the repo's `scripts/agent.zsh` at the reviewed
commit.

## Control matrix: agent path versus VS Code attach

The `agent` path closes every host channel except the mount it needs; the VS
Code path leaves five open. Nothing in either path closes the two egress
channels at the bottom.

| Channel | `agent` (plain Docker) | VS Code attach | Scenario |
| --- | --- | --- | --- |
| `.devcontainer` edits reach the next build | read-only mount, hash drift warning, review gate on rebuild | writable, no warning | 1, 4 |
| Firewall changed from inside | root only, sudo limited to the baked script | same | 2 |
| `.git/config`, `.git/hooks` executed by host git | read-only, `.git` is a mount point | writable | 3 |
| `initializeCommand` runs on the host | never read | runs at every reopen | 4 |
| `runArgs`, `mounts`, `remoteEnv` from the repo | ignored; options fixed in `agent.zsh` | honoured | 4 |
| SSH agent, keychain helper, `code` IPC | absent | present; `remoteEnv` only hides them | 5, 6 |
| `$BROWSER` opens host URLs | absent | present | 5 |
| `.gitconfig` | name and email only | whole file plus credential proxy | 6 |
| Published ports | `agent-ports` list, loopback, ephemeral | every opened port, auto-forwarded | 7 |
| Terminal escape sequences | tmux defaults off clipboard and passthrough | VS Code terminal, its own handling | 8 |
| GitHub-wide egress | open | open | 9 |
| DNS tunnelling via the resolver | open, narrowed to configured resolvers | same | 9 |
| Package code runs in the container | inside the boundary | inside the boundary | 10 |
| Extensions | none installed | four installed, agent can add more | 11 |
| Image inputs pinned | two sha256 pins; base and Claude Code by tag | same | 12 |
| Credentials readable by the agent | OAuth token, `gh` token, local settings | same, plus host keychain via helper | 13 |
| Host-side harness files | installed copy outside repos, symlinks refused | n/a | 14 |

## Verification checklist after a rebuild

Run these on the host and inside the container after `agent-rebuild`. Each
line maps to a scenario above; a failure means the control is not in place,
whatever the code says.

- [ ] `curl https://example.com` fails inside; `curl https://api.github.com/zen` works (firewall active, allowlist works)
- [ ] `timeout 5 bash -c 'exec 3<>/dev/tcp/gitlab.com/22'` fails at once, not by timeout (no blanket SSH; there is no `nc` in the image)
- [ ] `dig +short @1.1.1.1 example.com` returns nothing; `dig +short example.com` returns an address (DNS only to the configured resolver)
- [ ] `sudo /usr/local/bin/init-firewall.sh` on the live container ends with every "Verification passed" line (re-run works, fail-closed)
- [ ] If `ip -6 route show default` prints a route, `curl -6 https://api.github.com` fails (IPv6 blocked)
- [ ] `iptables -S` as `node` is denied; `sudo -l` lists only the firewall script (scenario 2)
- [ ] `touch .devcontainer/x`, `git config x.y z`, `mv .git .git.x` all fail inside (scenarios 1, 3)
- [ ] `env | grep -E 'SSH_AUTH_SOCK|VSCODE_IPC|REMOTE_CONTAINERS|GIT_ASKPASS|BROWSER'` prints nothing (scenario 5)
- [ ] `docker inspect <container> --format '{{.HostConfig.Privileged}} {{.HostConfig.NetworkMode}}'` prints `false bridge`; its mounts are the project folder, `.git`, the three read-only overlays and two volumes (scenario 4)
- [ ] `claude` sign-in and a normal session work without `sentry.io` and `statsig.com` on the allowlist
- [ ] `agent-stop` then `agent` prints "applying firewall" and the first three checks still hold
- [ ] `/pr` on a feature branch, `ccw test`, and `claude --worktree test` work with the read-only `.git/config`; report any config-write complaint
- [ ] `agent --setup`, `/init`, exit, plain `agent` refuses; `agent-rebuild` lists the `.devcontainer` changes and asks; afterwards `agent` attaches
- [ ] Edit a file under `.devcontainer` on the host, run `agent`: the drift warning appears and it still attaches
- [ ] With a port in `agent-ports`, `agent-recreate` then `agent-ports` shows a `127.0.0.1:<port>` mapping and the dev server answers there (also confirms inbound arrives from the gateway network)
- [ ] Inside tmux, `tmux show -g set-clipboard` prints `off` (scenario 8)
- [ ] On the host, `ls -l ~/.config/zsh/agent.zsh` is a regular file, mode 0644, and its SHA-256 matches `scripts/agent.zsh` at the reviewed commit (scenario 14)

## Open items and proposed next controls

The two egress channels in scenario 9 are the largest remaining gaps;
everything else residual is either inherent to the task or confined to the
VS Code path. In rough order of value per effort:

| Control | Closes | Cost and trade-off | Status |
| --- | --- | --- | --- |
| Filtering DNS resolver in the container (dnsmasq bound to loopback, answers only allowlisted names and GitHub; firewall allows upstream 53 only for its uid via `-m owner`) | DNS tunnelling (scenario 9) | one image layer above the marker, a start step in `init-firewall.sh`, a self-test; CDN hostnames with many aliases need listing | proposed, awaiting decision |
| Egress proxy for GitHub and npm that restricts GitHub to this project's repositories and npm to reads | GitHub-wide exfiltration (scenario 9) | large: GitHub API, web and git share hosts, so a CONNECT allowlist is not enough; needs URL rewriting to a proxy that enforces repository names, or a fine-grained token as the only credential | proposed, design first |
| Trim `.claude/settings.json` auto-allow (`curl`, `gh`, `node`, `npx`, `python`, `WebFetch`) | makes prompts meaningful on the VS Code path and in `agent --setup` | a prompt on most tool calls; pointless where `CLAUDE_SHORTCUT_FLAGS` skips prompts anyway | decision needed |
| Digest-pin `node:22-bookworm` and pin `CLAUDE_CODE_VERSION` | base-image and Claude Code supply chain (scenario 12) | a hash to bump on every refresh; `cc-update` still works between rebuilds | easy, not started |
| `--security-opt no-new-privileges` and a user-namespace remap in `agent.zsh` | privilege escalation inside the container (scenario 2) | `no-new-privileges` breaks `sudo`, so the firewall would have to run from `agent.zsh` as `docker exec -u root` only (which it already can); userns remap changes bind-mount ownership on Linux hosts, usually harmless on Docker Desktop | investigate |
| Fine-grained GitHub token scoped to this repository for `gh auth` inside the container | blast radius of a leaked token (scenario 13) | per-project token management | user practice, document in README |
| Read-only `.vscode/` overlay on the agent path | host-executed editor tasks (scenario 3) | breaks editing editor settings from inside; few projects need that | cheap, decide |
| VS Code path: a documented pre-rebuild check (`git diff -- .devcontainer`, `grep initializeCommand`) or a host-side git hook that blocks a rebuild on unreviewed changes | scenarios 1, 4 on the VS Code path | process, not code; the hook needs a host-side install step | document now |

Out of scope and accepted: the model's own access to repository contents and
the conversation, the user's browser as the viewer of agent-served pages,
and the terminal emulator's parser.
