- **`scripts/agent.zsh`: run the dev container from the host without VS
  Code.** `agent` builds, creates, starts and attaches (tmux inside) with
  plain Docker: only the project folder, two named volumes and
  `NET_ADMIN`/`NET_RAW` — none of the host channels a VS Code attach opens
  (SSH agent, keychain credential helper, `code` IPC, `$BROWSER`).
  `.devcontainer/`, `.git/hooks/` and `.git/config` are mounted read-only
  (and `.git` itself is a mount point, so it can't be renamed and replaced)
  so an agent can't change what the next rebuild or the host's git runs. The
  firewall is re-applied whenever the OUTPUT policy isn't DROP (checked, not
  assumed); the image is labelled with a hash of `.devcontainer/` and `agent`
  warns on drift. `agent --setup` creates a one-time container without the
  overlays and with prompts on, for `/init` and the detach script; plain
  `agent` refuses to attach to it until `agent-rebuild`; `agent-rebuild` and
  `agent-recreate` list `.devcontainer` changes since the last build and ask
  first, and `agent` refuses a same-named container that mounts another
  folder. Also
  `agent-rebuild`, `agent-recreate`, `agent-stop`, `agent-ports`,
  `agent-shell`; ports come from the per-project
  `.devcontainer/agent-ports` (loopback, ephemeral host port).
  `scripts/sync-harness.sh --install-shell` installs it to
  `~/.config/zsh/agent.zsh` (plain copy, diff + backup on update, symlinks
  refused, host only) and offers the `~/.zshrc` line; a normal sync offers
  the same at the end. Tested against a stub `docker`
  (`scripts/tests/agent_zsh_test.zsh`).
