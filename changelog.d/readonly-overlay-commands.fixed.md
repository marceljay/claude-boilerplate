- **Commands no longer write `.git/config` or assume `$BROWSER`.** With
  `.devcontainer/`, `.git/hooks/` and `.git/config` read-only under
  `agent-sandbox.zsh`: `/pr` pushes with `git push origin HEAD` (no `-u`) and passes
  `--head` to `gh pr create`; `ccw` adds worktrees with `--no-track`; `/init`
  probes whether `.devcontainer` is writable and otherwise emits the exact
  edits for the user to apply on the host (or says to run in `agent-sandbox
  --setup`); `/dev` prints the container port and the `docker port
  $AGENT_SANDBOX_CONTAINER_NAME <port>` command when `$BROWSER` is unset and points
  at `.devcontainer/agent-sandbox-ports`. `claude-harness.zsh`'s header no longer
  claims "no host access" and `cc-help` describes what a firewall re-run
  does.
