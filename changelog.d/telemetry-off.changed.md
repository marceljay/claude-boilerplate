- **Claude Code telemetry and error reporting are switched off; `sentry.io`
  and `statsig.com` leave the firewall allowlist.** Both hosts accept posts
  from anyone with their own project key, so an open path to them was an
  exfiltration channel. `DISABLE_ERROR_REPORTING=1` and `DISABLE_TELEMETRY=1`
  are set in `devcontainer.json`'s `containerEnv` and by `agent.zsh`
  (names verified against the Claude Code docs; the umbrella
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` was not used because it also
  disables `/feedback` and update checks). Side effect: `DISABLE_TELEMETRY`
  stops feature-flag evaluation, so Remote Control is unavailable in the
  container. `api.x.ai` moved to a commented optional entry; the VS Code
  marketplace hosts stay, marked as needed only for the VS Code attach path.
  `devcontainer.json` also gains a commented-out hardened `remoteEnv` block
  (blank `BROWSER`, `SSH_AUTH_SOCK`, `VSCODE_IPC_HOOK_CLI`,
  `REMOTE_CONTAINERS_IPC`, `GIT_ASKPASS`) with a note that it only hides the
  channels and breaks `/dev`'s browser opening — off by default.
