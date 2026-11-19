- **`agent-sandbox` shells show UTF-8 instead of `_`.** `docker exec`
  started tmux and zsh with no locale and `TERM=xterm`, so the tmux client
  replaced every non-ASCII character with `_`. `agent-sandbox` now passes
  `LANG=C.UTF-8`, `TERM=xterm-256color` and the host's `COLORTERM`.
  `sync-harness.sh --install-shell` now reminds you that already open shells
  keep the old functions until you `source` the file or open a new tab.
