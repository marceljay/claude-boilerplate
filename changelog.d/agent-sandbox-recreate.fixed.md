- **`agent-sandbox-recreate` and `agent-sandbox-rebuild` ask before ending
  a live session.** When Claude Code is still running in the container,
  they say that removing it ends the session and wait for a yes (default
  No); `claude --continue` resumes the conversation afterwards. When the
  read-only `.git/config` mount is missing, `agent-sandbox` now names the
  usual cause: a host git command (`git init`, `git remote add`,
  `push -u`, `git config`) rewrote the file, which detaches the mount.
  agent-sandbox.zsh 1.6.1 — reinstall it with
  `scripts/sync-harness.sh --install-shell`.
