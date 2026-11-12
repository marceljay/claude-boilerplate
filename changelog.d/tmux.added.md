- **`tmux` in the image, with a hardened `/etc/tmux.conf`.** `agent.zsh`
  attaches to a tmux session so a closed terminal tab doesn't end the Claude
  session. The root-owned config sets `default-shell /bin/zsh`,
  `history-limit 50000`, `mouse on`, and turns off `set-clipboard` (no OSC 52
  writes to the host clipboard) and `allow-passthrough` (no raw escape
  sequences relayed to the host terminal); both are defaults any pane can
  change with `tmux set`, not a boundary.
