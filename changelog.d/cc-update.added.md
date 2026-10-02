- **`cc-update [version]` updates Claude Code inside the container.** Manual
  updates kept breaking: `claude update` and a bare `npm install -g` run from
  `/workspace`, where the repo's `.npmrc` (`ignore-scripts=true`) stops the
  postinstall that links the platform-native binary, leaving "native binary
  not installed". The new shell function (in `claude-harness.zsh`, next to
  `cc`/`ccw`) runs the same hardened install the Dockerfile uses — from
  `$HOME`, with the postinstall explicitly allowed — retries once after
  clearing a half-installed package, and verifies with `claude --version`.
  The Dockerfile now also sets `DISABLE_UPDATES=1`: `DISABLE_AUTOUPDATER`
  only stopped the background check, so a manual `claude update` could still
  brick the install; now it refuses. `CLAUDE_CODE_VERSION` in
  `devcontainer.json` stays `latest` (a per-rebuild snapshot) with a comment
  on when to pin instead. Documented in `.claude/README.md` §7 and `cc-help`.
