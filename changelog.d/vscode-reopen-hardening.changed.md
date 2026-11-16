- **VS Code "Reopen in Container" now needs a per-host opt-in and carries
  the same read-only overlays as `agent`.** `devcontainer.json` gains an
  `initializeCommand` that runs the new `.devcontainer/initialize.sh` on
  the host before every create and start: it refuses unless
  `AGENT_ALLOW_VSCODE=1` is set or `~/.config/zsh/agent-allow-vscode`
  exists (both outside the repository, so a cloned repo cannot flip it),
  refuses a `.git/commondir` or `.git/worktrees/*/commondir` that
  redirects git, creates the `.git/commondir` placeholder and `.vscode/`
  when missing, and never runs git. The `mounts` list binds `.git` as its
  own mount point and `.devcontainer`, `.vscode`, `.git/config`,
  `.git/hooks` and `.git/commondir` read-only, so what the host executes
  cannot be changed from inside on either path. `/init` therefore hands
  `.devcontainer` edits to the host on the reopen path too; `agent --setup`
  stays the writable container. `sync-harness.sh` mirrors `initialize.sh`
  and warns when a kept `devcontainer.json` lacks the wiring.
  Tests: `scripts/tests/initialize_sh_test.sh`. Still missing on the
  reopen path: the nested-repository check, `.git/modules/**/config`
  mounts and the drift gate.
