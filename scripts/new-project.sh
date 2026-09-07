#!/usr/bin/env bash
# Detach this copy of the boilerplate into a fresh project.
#
# Removes/resets the files that describe the *boilerplate* so /init can
# scaffold real ones for *your* project:
#   - README.md   -> renamed to BOILERPLATE.md (keeps dev-container/firewall docs)
#   - LICENSE     -> removed (add your project's own)
#   - CHANGELOG.md, _planning/STATUS.md, _planning/ -> reset to empty templates
#
# By default it also deletes .git and re-inits, so your project starts with
# a clean history instead of the boilerplate's.
#
# Usage: scripts/new-project.sh [-y] [--keep-git]
#   -y          skip the confirmation prompt
#   --keep-git  keep the boilerplate's git history instead of re-initializing

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .boilerplate-dev ]; then
  echo "REFUSED: .boilerplate-dev marks this as the boilerplate's own dev repo —" >&2
  echo "detaching would reset its git history. Delete the marker if you really mean it." >&2
  exit 1
fi

YES=0
KEEP_GIT=0
for arg in "$@"; do
  case "$arg" in
    -y) YES=1 ;;
    --keep-git) KEEP_GIT=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "This will detach the boilerplate in: $(pwd)"
echo "  - rename README.md -> BOILERPLATE.md"
echo "  - delete LICENSE (add your own afterwards)"
echo "  - reset CHANGELOG.md and _planning/STATUS.md to empty templates"
[ "$KEEP_GIT" -eq 0 ] && echo "  - DELETE .git and re-init (boilerplate history is dropped; --keep-git retains it)"
if [ "$YES" -ne 1 ]; then
  printf "Continue? [y/N] "
  read -r reply
  case "$reply" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
fi

TODAY="$(date +%F)"

[ -f README.md ] && mv README.md BOILERPLATE.md
[ -f LICENSE ] && rm LICENSE

# Rename the dev container from the boilerplate default to this project's folder
# name. The default name ("Claude Boilerplate Repo") is what the first-run hook
# keys off to detect an un-detached copy, so renaming it also turns that nudge off.
PROJECT_NAME="$(basename "$(pwd)")"
dc=".devcontainer/devcontainer.json"
if [ -f "$dc" ]; then
  # Escape sed's replacement metacharacters (& \ /) — a folder called "a&b" or
  # "x/y" must not corrupt the JSON or abort the script half-detached.
  safe_name="$(printf '%s' "$PROJECT_NAME" | sed 's/[&\/\\]/\\&/g')"
  sed -i.bak "s/\"name\": \"Claude Boilerplate Repo\"/\"name\": \"${safe_name}\"/" "$dc"
  rm -f "$dc.bak"
fi

mkdir -p _planning
cat > _planning/STATUS.md <<EOF
# Project Status

Last updated: ${TODAY}

## In Progress

_None_

## Needs input

_None_

## Blockers

_None_

---

# Backlog

_The only queue of future work, priority-ordered. Top High-Priority item = next up._

## High Priority

## Medium Priority

## Low Priority / Ideas
EOF

cat > CHANGELOG.md <<'EOF'
# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added
- Initial project setup
EOF

mkdir -p _planning/plans _planning/specs
find _planning/plans -type f ! -name '.gitkeep' -delete
touch _planning/plans/.gitkeep _planning/specs/.gitkeep

if [ "$KEEP_GIT" -eq 0 ]; then
  rm -rf .git
  git init -q
fi

echo
echo "Done. Next steps:"
echo "  1. Run /init in Claude Code to scaffold README.md etc. for your stack."
echo "  2. Add a LICENSE for your project."
echo "  3. Dev container renamed to \"${PROJECT_NAME}\" — reopen/rebuild the"
echo "     container so VS Code picks up the new name."
echo "  4. Harness docs remain in .claude/README.md; dev-container docs in BOILERPLATE.md."

# Self-remove: this script is one-shot boilerplate, not part of your project.
rm -- "$0"
rmdir scripts 2>/dev/null || true
