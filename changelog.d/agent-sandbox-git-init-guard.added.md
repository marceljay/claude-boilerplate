- **Host-side `git init` guard.** Sourcing `agent-sandbox.zsh` now asks
  before `git init` runs in a folder that is already a repository: it
  changes nothing useful there but rewrites `.git/config`, which detaches
  an agent-sandbox container's read-only mount until
  `agent-sandbox-recreate`. A fresh `git init`, every other git command and
  non-interactive use pass through; `command git init` bypasses it once,
  `AGENT_SANDBOX_GIT_INIT_GUARD=0` turns it off. `agent-sandbox --version`
  shows the loaded version, flags a stale shell and an inactive guard.
  agent-sandbox.zsh 1.7.1.
  The README's optional per-command check is now
  `AGENT_SANDBOX_GIT_CHECK=1`; an existing `git() { agent-sandbox-check -q
  … }` line placed before the `source` line is taken over automatically.
