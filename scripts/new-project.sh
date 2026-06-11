#!/usr/bin/env bash
# Detach this copy of the boilerplate into a fresh project.
#
# Removes/resets the files that describe the *boilerplate* so /init can
# scaffold real ones for *your* project:
#   - README.md   -> renamed to BOILERPLATE.md (keeps dev-container/firewall docs)
#   - LICENSE     -> removed (add your project's own)
#   - CHANGELOG.md, STATUS.md, _planning/ -> reset to empty templates
#
# Usage: scripts/new-project.sh [-y] [--fresh-git]
#   -y           skip the confirmation prompt
#   --fresh-git  also delete .git and re-init (drops boilerplate history)

set -euo pipefail
cd "$(dirname "$0")/.."

YES=0
FRESH_GIT=0
for arg in "$@"; do
  case "$arg" in
    -y) YES=1 ;;
    --fresh-git) FRESH_GIT=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "This will detach the boilerplate in: $(pwd)"
echo "  - rename README.md -> BOILERPLATE.md"
echo "  - delete LICENSE (add your own afterwards)"
echo "  - reset CHANGELOG.md, STATUS.md, _planning/ to empty templates"
[ "$FRESH_GIT" -eq 1 ] && echo "  - DELETE .git and re-init (history is lost)"
if [ "$YES" -ne 1 ]; then
  printf "Continue? [y/N] "
  read -r reply
  case "$reply" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
fi

TODAY="$(date +%F)"

[ -f README.md ] && mv README.md BOILERPLATE.md
[ -f LICENSE ] && rm LICENSE

cat > STATUS.md <<EOF
# Project Status

Last updated: ${TODAY}

## In Progress
_None yet_

## Blockers
_None_

Next: top of \`_planning/backlog.md\`.
EOF

cat > CHANGELOG.md <<'EOF'
# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added
- Initial project setup
EOF

mkdir -p _planning/plans
find _planning/plans -type f ! -name '.gitkeep' -delete
touch _planning/plans/.gitkeep
cat > _planning/backlog.md <<'EOF'
# Backlog

## High Priority
- Initial project setup

## Medium Priority

## Low Priority / Ideas
EOF

if [ "$FRESH_GIT" -eq 1 ]; then
  rm -rf .git
  git init -q
fi

echo
echo "Done. Next steps:"
echo "  1. Run /init in Claude Code to scaffold README.md etc. for your stack."
echo "  2. Add a LICENSE for your project."
echo "  3. Harness docs remain in .claude/README.md; dev-container docs in BOILERPLATE.md."

# Self-remove: this script is one-shot boilerplate, not part of your project.
rm -- "$0"
rmdir scripts 2>/dev/null || true
