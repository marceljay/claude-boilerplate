- **Linux hosts are first-class for `agent.zsh`.** The image takes
  `USER_UID`/`USER_GID` build args and renumbers the `node` user, and
  `agent` passes the host's ids on Linux (native Docker Engine keeps host
  ownership on bind mounts, so a uid-1000 container could not write a repo
  owned by uid 1001); the image is labelled with the uid it was built for
  and `agent` warns on mismatch. `sync-harness.sh --install-shell` detects a
  bash login shell and offers a `~/.bashrc` block that runs the functions
  through `zsh -c`. README and `docs/SECURITY-MODEL.md` are host-neutral,
  with Linux notes: shared kernel (no VM), the gateway being the host,
  Docker-group hygiene, terminal and credential-helper equivalents.
