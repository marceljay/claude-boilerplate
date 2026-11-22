- **`agent-sandbox` refuses to attach when a read-only mount is missing
  inside the container.** Docker Desktop was seen to drop the read-only
  `.git/config` mount on a container restart while `docker inspect` still
  listed it, which left `.git/config` writable from inside: an agent could
  set `core.fsmonitor` or `core.hooksPath` and have the host's git or VS
  Code run it. Every normal-mode attach now reads the container's own
  `/proc/1/mountinfo` and refuses, pointing at `agent-sandbox-recreate`,
  when `.devcontainer`, `.vscode`, `.git/hooks`, `.git/config`,
  `.git/commondir` or a `.git/modules/**/config` is not mounted or mounted
  writable. `agent-sandbox.zsh` is now version 1.6.0 (the UTF-8 fix
  had shipped without a version change, so the installed copy reported
  1.5.0 whether it had the fix or not).
