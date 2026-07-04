#!/usr/bin/env bash
# Fired by the SessionStart hook (see .claude/settings.json) at the start of a
# session. Its job: if this repo is still an un-detached copy of the boilerplate,
# nudge the user to run /init before building, so the template README/LICENSE and
# the boilerplate's git history don't silently carry into their project.
#
# Signal: the dev container is still named "Claude Boilerplate Repo" (the
# boilerplate default that ships in devcontainer.json). /init and
# scripts/new-project.sh rename it to the project, so the default name persisting
# means "not set up yet." This is more durable than the self-deleting detach
# script and survives manual deletion of it.
set -euo pipefail

# The boilerplate's own dev repo keeps the default container name forever (it's
# the detection signal that must ship to copies). A gitignored marker — which
# clones/copies never inherit — tells us apart from an un-detached copy.
[[ -f ".boilerplate-dev" ]] && exit 0

dc=".devcontainer/devcontainer.json"
if [[ -f "$dc" ]] && grep -q '"name"[[:space:]]*:[[:space:]]*"Claude Boilerplate Repo"' "$dc"; then
  cat <<'EOF'
FIRST_RUN_BOILERPLATE: This repo is still an un-detached copy of the boilerplate
(its dev container is still named "Claude Boilerplate Repo"). Before building, tell
the user they can run /init to set the project up — it offers to detach first
(remove the template README/LICENSE and reset the boilerplate's git history),
renames the dev container to their project, and scaffolds their project files.
Mention this once; don't nag every turn.
EOF
fi
