- **README documents the security model honestly.** New "Run without VS
  Code (recommended)" section (install, commands, setup mode, ports, drift
  warnings, what you give up) and a "Security model" section listing the VS
  Code host channels, the bind-mount risks (`.devcontainer`, `.git/hooks`,
  `.git/config` are executed by the host), and the firewall's known limits
  (GitHub-wide egress, DNS tunnelling until a filtering resolver exists);
  the firewall section no longer lists SSH, telemetry hosts or "the host
  LAN" as allowed. macOS notes: iTerm2 3.6.10+, no `tmux -CC` for agent
  sessions, window-title reporting off, what Docker Desktop's first-run
  prompt grants. `.claude/README.md` §7, `CLAUDE.md`'s runtime bullet and
  STACKS.md cover both container paths.
