- **`agent-sandbox.zsh` never runs git inside the project on the host, and detects
  the two bypasses of the read-only mounts.** A second review showed that `agent-sandbox-rebuild`'s
  review gate ran `git status` in the repo before anything was reviewed —
  after `agent-sandbox --setup`, where `.git/config` is writable, that call would
  have executed a planted `core.fsmonitor`. The gate now diffs against copies
  kept outside the repo (`~/.cache/agent-sandbox/<name>/`: `.devcontainer` from
  the last build; `.git/config` and `.git/hooks` from before a setup
  container) and asks; the only git call left is `git config --global`,
  run from `/`. `agent-sandbox` and the gate refuse when `.git/commondir` exists
  with anything but `.` (a one-file redirect of git's config and hooks past
  the read-only mounts) and warn about nested repositories (a submodule
  entry makes the host's `git status` read their config). Both bypasses
  are documented in `docs/SECURITY-MODEL.md` scenario 3 with the decisions
  still open: a read-only `commondir` placeholder, and a policy for nested
  repositories.
