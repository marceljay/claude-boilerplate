#!/usr/bin/env bash
# Fired by the SessionStart hook (see .claude/settings.json) at the start of a
# session. Its job: if this repo is still an un-detached copy of the boilerplate,
# nudge the user to run /init before building, so the template README/LICENSE and
# the boilerplate's git history don't silently carry into their project.
#
# Signal: scripts/new-project.sh exists. That script self-deletes once the repo
# is detached (see /init step 0), so its presence means "not set up yet."
set -euo pipefail

if [[ -f scripts/new-project.sh ]]; then
  cat <<'EOF'
FIRST_RUN_BOILERPLATE: This repo is still an un-detached copy of the boilerplate
(scripts/new-project.sh is present). Before building, tell the user they can run
/init to set the project up — it offers to detach first (remove the template
README/LICENSE and reset the boilerplate's git history) and then scaffolds their
own project files. Mention this once; don't nag every turn.
EOF
fi
