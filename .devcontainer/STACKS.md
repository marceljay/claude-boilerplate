# Adding a Stack to the Dev Container

The container is **Node-first**: Node/npm is preinstalled (Claude Code itself is
an npm package) and the firewall passes only npm's registry. Every other stack
is one rebuild away — this file holds the tested recipe per stack.

## Why a recipe is needed (read once)

Two independent layers must both be handled, and they fail differently:

1. **Toolchain (build time).** Compilers/interpreters install during
   `docker build`, which runs on the host network — the firewall does **not**
   apply there. Install via a [dev container feature](https://containers.dev/features)
   in `devcontainer.json` (easiest) or apt/tarball lines in the `Dockerfile`.
2. **Package registry (runtime).** Once the container is running, the
   default-deny firewall blocks every host not in the `allowed_domains` array
   in `init-firewall.sh`. Package managers typically need **two** domains — a
   metadata/index host *and* a separate download/CDN host. Missing the second
   is the classic trap: the index resolves, then the first real download hangs
   forever with no error.

Both edits land only after a **container rebuild** ("Rebuild Container" in the
editor): the firewall script is baked into the image at `/usr/local/bin/` and
that copy is what runs on start — editing the repo copy alone changes nothing.

Git dependencies need no firewall change (GitHub's IP ranges are allowlisted
wholesale at startup).

## The recipe

1. Add the stack's **feature** to `devcontainer.json` (or Dockerfile lines).
2. Add the stack's **domains** to the `allowed_domains` array in
   `init-firewall.sh`, under the stacks comment block.
3. **Rebuild** the container.
4. **Verify end-to-end** with the stack's check below — it must download a real
   package, not just print a version, or you haven't tested the firewall.
5. Record the decision as a one-liner in the project `CLAUDE.md`
   (e.g. `Stack: python`) so future sessions know what the container is
   supposed to provide.

If a download hangs mid-install later, suspect the firewall first: the
allowlist resolves DNS once per container start, so big CDNs that rotate IPs
can drift — restarting the container re-resolves them.

## Python

- **Toolchain:** feature `"ghcr.io/devcontainers/features/python:1": {}`
  — or Dockerfile: `apt-get install -y python3-pip python3-venv`
  (Debian's bare `python3` ships without pip *and* without `ensurepip`).
- **Firewall:** `pypi.org` (index) **and** `files.pythonhosted.org` (wheels).
- **Verify:** `python3 -m venv /tmp/v && /tmp/v/bin/pip install requests`

## Go

- **Toolchain:** feature `"ghcr.io/devcontainers/features/go:1": {}`
- **Firewall:** `proxy.golang.org` (module proxy) **and** `sum.golang.org`
  (checksum db).
- **Verify:** `cd $(mktemp -d) && go mod init t && go get golang.org/x/text@latest`

## Rust

- **Toolchain:** feature `"ghcr.io/devcontainers/features/rust:1": {}`
  (rustup's own domains matter only at build time — unrestricted).
- **Firewall:** `index.crates.io` (sparse index) **and** `static.crates.io`
  (crate downloads). Add `crates.io` too if you'll `cargo publish` or use its API.
- **Verify:** `cargo new /tmp/t && cd /tmp/t && cargo add anyhow && cargo build`

## Java / JVM

- **Toolchain:** feature `"ghcr.io/devcontainers/features/java:1": {}`
  (options for Maven/Gradle).
- **Firewall:** Maven Central: `repo.maven.apache.org` and `repo1.maven.org`.
  Gradle additionally: `plugins.gradle.org` and `services.gradle.org`
  (wrapper distributions).
- **Verify:** `mvn dependency:get -Dartifact=org.apache.commons:commons-lang3:3.14.0`

## Ruby

- **Toolchain:** feature `"ghcr.io/devcontainers/features/ruby:1": {}`
- **Firewall:** `rubygems.org` **and** `index.rubygems.org`.
- **Verify:** `gem install --user-install rake`

## Any other stack

Same pattern: toolchain at build time, registry domains in the firewall,
verify with a real download. When hunting the domains, check the package
manager's docs for **all** hosts it contacts — index and download hosts almost
always differ (see the Python trap above). Private registries and mirrors need
their domains added the same way.

## Supply-chain hardening

Compromised package versions are usually detected and yanked within
hours-to-days of publication, so the single best habit is **never be first to
install a fresh release** (a ~7-day minimum age), and the second is **don't
let installs execute code**. The container's default-deny firewall is the
backstop, not the defense: a malicious script that runs can't reach
non-allowlisted exfiltration hosts, but it can still read your workspace.

Baseline for every stack: commit the lockfile and use frozen installs in CI
(`npm ci`, `pnpm install --frozen-lockfile`, `yarn --immutable`,
`cargo --locked`) — then new versions only enter via deliberate update PRs,
which is exactly where an age rule can be enforced.

- **npm** — the repo ships a root `.npmrc` with `ignore-scripts=true` (no
  postinstall code execution) and `save-exact=true`. For the few packages
  that need a build step: `npm install-scripts approve <pkg>` once (records
  it under `allowScripts` in `package.json` — npm ≥ 12 blocks unlisted
  scripts regardless of `ignore-scripts`), then
  `npm rebuild <pkg> --ignore-scripts=false`. npm has no rolling age gate,
  only a fixed cutoff (`npm install --before=<date>`); get the age rule from
  pnpm or an update bot (below).
- **pnpm** — the strongest native option. In `pnpm-workspace.yaml`:
  `minimumReleaseAge: 10080` (minutes = 7 days; pnpm ≥ 10.16) hides younger
  versions from resolution entirely; `minimumReleaseAgeExclude` lists escape
  hatches. pnpm ≥ 10 already skips postinstall scripts unless allowlisted
  (`onlyBuiltDependencies`).
- **Yarn (Berry)** — `enableScripts: false` in `.yarnrc.yml`
  (per-package opt-in via `dependenciesMeta`); no built-in age gate — use an
  update bot.
- **Go** — nothing to configure: no install scripts, `go.sum` verified against
  a transparency log, and minimum-version selection means a fresh release
  never flows in implicitly — only an explicit `go get pkg@latest` does, so
  simply don't upgrade day-zero. Run `govulncheck` for the reverse risk.
- **Rust** — no native age gate, and `build.rs`/proc-macros execute at build
  time, so the exposure is real: `--locked` everywhere in CI, `cargo-deny`
  for policy, `cargo-vet` if you want review-based gating.
- **Python (uv)** — `exclude-newer = "<timestamp>"` under `[tool.uv]` (fixed
  cutoff like npm's `--before`; compute it in CI for a rolling window).

**The universal age gate** is the dependency-update bot, since with lockfiles
that's the only door new versions come through: Renovate
`"minimumReleaseAge": "7 days"` or Dependabot's `cooldown` (`default-days: 7`)
— both apply across npm, cargo, gomod, pip, and more.

### Active scanning (Socket) — opt-in

Everything above is *preventive* and passive: don't run install code, don't be
first to a release. [Socket](https://socket.dev) is the *detective* half — it
analyzes what a package's code actually does (install scripts, network and
filesystem access, obfuscation, credential reads) and flags the behavior, so a
malicious release is caught before anyone files a CVE. The two are
complementary; neither replaces the other, and the age gate is still the
cheaper win if you only do one thing.

Not npm-only, despite the npm-shaped reputation: it reads `package.json` and
the JS lockfiles, plus `requirements.txt`/`pyproject.toml`/`uv.lock`,
`go.mod`, `pom.xml`, `Cargo.toml`, `Gemfile`, `packages.lock.json` and
Composer manifests. The **CLI** ships as an npm package though, so a Rust- or
Go-only project still pulls Node in to run it — fine in this container, worth
knowing elsewhere.

```sh
npm install -g socket          # MIT; no install scripts, so ignore-scripts is fine
socket package npm/left-pad@1.3.0   # vet one package before adding it
socket scan create             # scan the whole project's manifests
socket npm install <pkg>       # wrapper: audit, then hand off to npm
```

`socket npm`/`npx`/`pnpm`/`yarn` wrap the real package manager and exit
non-zero on a threat, which is what makes them usable as a CI gate.

Two things to know before committing to it:

- **It's a service, not a local scanner.** Analysis happens server-side, so it
  needs an API token (`SOCKET_CLI_API_TOKEN`) and it uploads your dependency
  manifest to a third party. Free tier is ~1K scans/month, and it's free for
  qualifying open-source projects.
- **The container firewall blocks it by default.** Uncomment the Socket
  domains in `init-firewall.sh` and rebuild, or every command hangs and then
  fails at the network layer.

**Exempt `socket` itself from the age gate — and know where that gate
reaches.** The install above is global, and nothing in this section governs a
global install: no lockfile, no `minimumReleaseAge`, no update bot. Add it as
a devDependency instead if you want it under the same rules as everything
else — and then exempt it, because a scanner inverts the rule's logic. Its
detection rules and threat intel ship *in* the releases (hence the fast
cadence — three published on 2026-07-10 alone), so a cooldown holds back
exactly the update that recognizes this week's attack: the gate ends up
defending against the tool that defends you.

```yaml
# pnpm-workspace.yaml
minimumReleaseAgeExclude: ["socket"]

# .github/dependabot.yml — exclude wins over include
cooldown:
  default-days: 7
  include: ["*"]
  exclude: ["socket"]
```

```json
// renovate.json — null clears the inherited minimumReleaseAge
{ "packageRules": [
  { "matchPackageNames": ["socket"], "minimumReleaseAge": null }
] }
```

Either route, the trade stays contained by pinning the exact version — the
repo's `save-exact=true` handles the devDependency case, the global install
needs it by hand (`npm install -g socket@1.1.143`) — so each bump is still a
deliberate, reviewable change. And the tarball runs no install scripts, so an
update only executes code once *you* run `socket`.

If sending manifests off-box is a non-starter, the fallback is the passive
gates above plus whatever your stack ships natively — `npm audit`,
`govulncheck`, `cargo-deny`, `pip-audit`. Those only know about published
CVEs, which is exactly the gap Socket exists to cover.
