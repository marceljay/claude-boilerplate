- **The two overlay bypasses are closed on the sandbox path, and a failed
  first firewall start fails closed on the VS Code path.** `agent-sandbox` creates
  a `.git/commondir` placeholder holding `.` and mounts it read-only, so git
  cannot be redirected to another config and hooks directory from inside;
  `.vscode/` is mounted read-only too (created empty when missing), closing
  editor tasks that run on folder open. Nested git repositories must be
  listed in the new per-project `.devcontainer/agent-sandbox-nested-repos` (paths or
  globs, read on the host); `agent-sandbox` and the rebuild gate refuse while an
  unlisted one exists, since a submodule entry would make the host's git
  read its config. `init-firewall.sh` gains an exit trap: when a first
  start fails before any rule exists it applies a loopback-only DROP table
  (recovery is a container restart); a failed re-run keeps the previous
  rules, and `agent-sandbox` treats the fail-closed table as "not applied" and
  stops the container. A read-only `.claude/` overlay was considered and
  deferred.
