#!/bin/sh
# Runs on the HOST before VS Code creates or starts the dev container
# ("initializeCommand" in devcontainer.json; the Dev Containers spec runs it
# on every create and every start). It is the only host-side step of the
# "Reopen in Container" path, and the read-only mounts in devcontainer.json
# depend on it:
#
#   1. Opt-in. Reopen is the less isolated path (host channels, see
#      docs/SECURITY-MODEL.md), so it must be enabled once per host: either
#      AGENT_ALLOW_VSCODE=1 in the environment VS Code sees, or the marker
#      file ${XDG_CONFIG_HOME:-$HOME/.config}/zsh/agent-allow-vscode. Without
#      either the container does not start. The switch lives on the host,
#      never in the repository, so a cloned repo cannot flip it.
#   2. Guards. .git must be a directory holding config and hooks (the mounts
#      need sources); .git/commondir, when present, must hold exactly "."
#      and every .git/worktrees/*/commondir must hold "../..". Anything else
#      redirects git on the host to a config directory the agent controls.
#   3. Sources. Creates the .git/commondir placeholder (".", no newline) and
#      an empty .vscode/ when missing, so the read-only mounts can bind.
#
# Plain POSIX sh; macOS, Linux and WSL. It never runs git: a planted
# core.fsmonitor or hooksPath is exactly what the guards exist for. The file
# sits in .devcontainer/, read-only inside the container, so the agent cannot
# edit it; review `git diff -- .devcontainer` before a rebuild regardless.
#
# Usage: initialize.sh [project-dir]   (default: current directory)

set -u

dir=${1:-.}
tag="initialize.sh:"
marker="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/agent-allow-vscode"

fail() { printf '%s %s\n' "$tag" "$*" >&2; exit 1; }

# 1. Opt-in -------------------------------------------------------------------
if [ "${AGENT_ALLOW_VSCODE:-}" != 1 ] && [ ! -f "$marker" ]; then
  fail "VS Code \"Reopen in Container\" is not enabled on this host.
  It opens channels from the container back to this machine (SSH agent,
  keychain, editor IPC, \$BROWSER); the recommended way to run the container
  is \`agent\` from a host terminal (README, \"Run without VS Code\"). To use
  reopen anyway, once per host:  touch \"$marker\"
  or set AGENT_ALLOW_VSCODE=1 in the environment VS Code is launched from."
fi

# 2. Guards -------------------------------------------------------------------
[ -d "$dir/.git" ] || fail "$dir/.git is not a directory: open the main worktree, not a linked one (the read-only mounts need .git/config and .git/hooks)"
[ -f "$dir/.git/config" ] && [ -d "$dir/.git/hooks" ] || fail "$dir needs .git/config and .git/hooks for the read-only mounts"

cd_file="$dir/.git/commondir"
if [ -e "$cd_file" ]; then
  # Exactly one byte: `$(cat)` would drop a trailing newline, and ".\n"
  # breaks git on 2.39 instead of being read as ".".
  if [ ! -f "$cd_file" ] || [ "$(wc -c < "$cd_file" | tr -d ' ')" != 1 ] || [ "$(cat "$cd_file")" != "." ]; then
    fail "DANGER: $cd_file exists and does not hold '.'. git on this host would read config and hooks from the directory it names (core.fsmonitor there runs as you). Inspect and remove it before running git in $dir."
  fi
fi
for w in "$dir"/.git/worktrees/*/commondir; do
  [ -e "$w" ] || continue
  [ "$(cat "$w")" = "../.." ] && continue
  fail "DANGER: $w does not hold '../..'. git run inside that worktree on this host would read config and hooks from the directory it names. Inspect and remove it first."
done

# 3. Sources ------------------------------------------------------------------
if [ ! -e "$cd_file" ]; then
  printf '.' > "$cd_file" || fail "cannot create $cd_file"
  printf '%s created %s placeholder (".") for the read-only mount\n' "$tag" "$cd_file"
fi
[ -d "$dir/.vscode" ] || mkdir -p "$dir/.vscode" || fail "cannot create $dir/.vscode"
exit 0
