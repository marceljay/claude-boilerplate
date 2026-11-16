- **`docs/SECURITY-MODEL.md`: the harness threat model.** Fourteen
  scenarios (firewall widening and bypass, `.git/config` and hooks,
  `initializeCommand`, VS Code sockets and `$BROWSER`, copied `.gitconfig`,
  published ports, terminal escape sequences, exfiltration through allowed
  egress, packages, extensions, image inputs, stored credentials, host-side
  harness files), each with vector, gain, current mitigation, residual risk
  and a hand check; a control matrix comparing the `agent-sandbox.zsh` and VS Code
  paths; the post-rebuild verification checklist; and the proposed next
  controls with their trade-offs. README's "Security model" links to it.
