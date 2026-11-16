- **The `agent` command family is renamed `agent-sandbox`.** Host-side
  commands are `agent-sandbox`, `agent-sandbox-setup`, `agent-sandbox-shell`,
  `agent-sandbox-rebuild`, `agent-sandbox-recreate`, `agent-sandbox-stop`,
  `agent-sandbox-ports`; the file is `scripts/agent-sandbox.zsh`, installed to
  `~/.config/zsh/agent-sandbox.zsh`; the per-project lists are
  `.devcontainer/agent-sandbox-ports` and `.devcontainer/agent-sandbox-nested-repos`;
  the environment variables are `AGENT_SANDBOX_CONTAINER_NAME`,
  `AGENT_SANDBOX_TZ` and `AGENT_SANDBOX_ALLOW_VSCODE`, the reopen marker file
  `~/.config/zsh/agent-sandbox-allow-vscode`, the image labels
  `agent-sandbox.*`, the host state directory `~/.cache/agent-sandbox/`.
  `agent` alone was too generic next to the AI agent the docs talk about.
  Migration: `sync-harness.sh --install-shell` offers to remove the old
  `agent.zsh` and rewrite the `.zshrc` line; a sync renames a target's
  `agent-ports` and `agent-nested-repos`. Container and volume names
  (`claude-<folder>`) do not change, so existing containers are picked up.
