- **No more intermittent "detected dubious ownership" from git in the
  agent-sandbox container.** The image marks `/workspace` as a safe git
  directory in the root-owned `/etc/gitconfig`; on Docker Desktop's
  virtiofs a bind-mounted file can briefly report another owner, and only
  VS Code's Dev Containers extension set this exception before. Needs
  `agent-sandbox-rebuild`.
