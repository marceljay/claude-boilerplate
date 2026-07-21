#!/usr/bin/env bash
#
# sync-harness.sh — install this boilerplate's harness (.claude/ +
# .devcontainer/) into an existing codebase, or refresh a sibling project's
# stale copy of it.
#
#   scripts/sync-harness.sh [--replace] ../my-project
#
# Run from the HOST, not inside a dev container: a container mounts only its
# own workspace, so sibling project directories aren't visible there.
#
# INSTALL (target has no .claude/ yet — e.g. an existing codebase adopting
# the harness, or a brand-new directory that is created if it doesn't exist):
# after one confirmation it copies .claude/ and .devcontainer/
# — and nothing else. Your .git, code, README, etc. are never touched. It
# strips this repo's recorded commit/testing-policy lines from the copied
# CLAUDE.md so /init asks fresh. Then reopen the project in its container
# and run /init to gap-fill (.gitignore security entries, _planning/,
# container rename, policies).
#
# REFRESH (target already has .claude/):
#   - MIRRORS the pure-harness dirs (.claude/{commands,skills,agents,hooks,
#     scripts}, plus .claude/README.md and .devcontainer/STACKS.md). Mirroring
#     also deletes files this repo has since retired (e.g. removed commands) —
#     it lists those and asks first.
#   - For files that usually carry PER-PROJECT edits — .devcontainer/
#     init-firewall.sh (custom allowlist domains), devcontainer.json
#     (container name, stack features), Dockerfile (stack toolchains),
#     .claude/CLAUDE.md (commit/testing policy), .claude/settings.json
#     (permissions), .npmrc (registry/auth config) — it shows a diff and asks
#     before overwriting. Default is always KEEP the target's version.
#   - Never touches: settings.local.json, .claude/logs/, _planning/,
#     project code, git state.
#
# REPLACE (--replace; target has a harness you want gone — a foreign/
# hand-rolled .claude/, or one whose conventions you're abandoning): backs
# up the target's .claude/ and .devcontainer/ to a timestamped tar.gz at the
# target root, removes both dirs, then proceeds as a fresh INSTALL (policy
# lines stripped — /init re-asks, which is also how you replace sloppy
# commit/testing rules). Still never touches code, .git, or _planning/.
# To overwrite only ONE file's conventions (e.g. just CLAUDE.md), plain
# refresh mode already covers it: answer y at that file's diff prompt.
#
# TODO(backlog): once the firewall's domain allowlist lives in its own data
# file, init-firewall.sh can move to the mirror group and only the domain
# file stays ask-first.

set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"

REPLACE=0
if [ "${1:-}" = "--replace" ]; then
  REPLACE=1
  shift
fi
if [ $# -ne 1 ]; then
  echo "usage: $0 [--replace] <target-project-dir>" >&2
  exit 1
fi
if [ -e "$1" ] && [ ! -d "$1" ]; then
  echo "error: '$1' exists but is not a directory" >&2
  exit 1
fi
if [ ! -d "$1" ]; then
  echo "'$1' does not exist — creating it."
  mkdir -p "$1"
fi
TARGET="$(cd "$1" && pwd)"

if [ "$TARGET" = "$SRC" ]; then
  echo "error: target is this repo itself" >&2
  exit 1
fi

# Prompt helper: default No; piped/EOF input also means No.
ask() {
  local reply=""
  printf '%s [y/N] ' "$1"
  read -r reply || reply=n
  case "$reply" in
    y | Y | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

ADOPT=0
if [ "$REPLACE" = 1 ] && { [ -d "$TARGET/.claude" ] || [ -d "$TARGET/.devcontainer" ]; }; then
  old_dirs=""
  [ -d "$TARGET/.claude" ] && old_dirs=".claude"
  [ -d "$TARGET/.devcontainer" ] && old_dirs="$old_dirs .devcontainer"
  backup="harness-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  echo "REPLACE: the target's existing ${old_dirs# } will be removed and replaced"
  echo "with this boilerplate's harness. Code, .git and _planning/ stay untouched."
  echo "Backup first: $TARGET/$backup"
  ask "Replace the harness in $TARGET?" || exit 1
  (cd "$TARGET" && tar -czf "$backup" $old_dirs && rm -rf $old_dirs)
  ADOPT=1
  echo
elif [ ! -d "$TARGET/.claude" ]; then
  echo "$TARGET has no .claude/ yet — fresh install into an existing codebase."
  echo "Only .claude/ and .devcontainer/ will be created; .git, code, README"
  echo "and everything else stay untouched."
  ask "Install the harness into $TARGET?" || exit 1
  ADOPT=1
  echo
fi

echo "Syncing harness: $SRC -> $TARGET"
echo

# --- 1. Mirror the pure-harness directories --------------------------------
MIRROR_DIRS=".claude/commands .claude/skills .claude/agents .claude/hooks .claude/scripts"

# Relative file list of a dir, minus caches/cruft. Runs in a subshell (cd).
list_files() {
  (cd "$1" && find . -type f ! -path '*__pycache__*' ! -name '.DS_Store' | sort)
}

for d in $MIRROR_DIRS; do
  [ -d "$SRC/$d" ] || continue
  mkdir -p "$TARGET/$d"
  # Files that exist only in the target: retired upstream, or the project's
  # own additions — ask before removing them.
  deletions=$(comm -13 <(list_files "$SRC/$d") <(list_files "$TARGET/$d"))
  if [ -n "$deletions" ]; then
    echo "$d: target-only files (retired upstream, or this project's own?):"
    echo "$deletions" | sed 's/^/    /'
    if ask "  Delete them in the target?"; then
      echo "$deletions" | (cd "$TARGET/$d" && xargs rm -f --)
    fi
  fi
  (cd "$SRC/$d" && tar --exclude='__pycache__' --exclude='.DS_Store' -cf - .) |
    (cd "$TARGET/$d" && tar -xf -)
  echo "mirrored  $d"
done

for f in .claude/README.md .devcontainer/STACKS.md; do
  [ -f "$SRC/$f" ] || continue
  mkdir -p "$TARGET/$(dirname "$f")"
  cp -p "$SRC/$f" "$TARGET/$f"
  echo "copied    $f"
done

# --- 2. Ask-first files (commonly hold per-project edits) ------------------
ASK_FILES=".devcontainer/init-firewall.sh .devcontainer/devcontainer.json .devcontainer/Dockerfile .claude/CLAUDE.md .claude/settings.json .npmrc"

echo
for f in $ASK_FILES; do
  [ -f "$SRC/$f" ] || continue
  if [ ! -f "$TARGET/$f" ]; then
    mkdir -p "$TARGET/$(dirname "$f")"
    cp -p "$SRC/$f" "$TARGET/$f"
    echo "copied    $f (was missing in target)"
  elif cmp -s "$SRC/$f" "$TARGET/$f"; then
    echo "in sync   $f"
  else
    echo
    echo "differs   $f (target may hold per-project edits, e.g. firewall domains)"
    diff -u "$TARGET/$f" "$SRC/$f" | head -60 || true
    if ask "  Overwrite the target's $f with the boilerplate version?"; then
      cp -p "$SRC/$f" "$TARGET/$f"
      echo "overwrote $f"
    else
      echo "kept      $f (target version)"
    fi
  fi
done

# --- 3. Install-mode fixups -------------------------------------------------
if [ "$ADOPT" = 1 ]; then
  # The copied CLAUDE.md records THIS repo's per-project choices — strip them
  # so /init asks the adopting project fresh.
  sed -i.bak -e '/^- Commit policy:/d' -e '/^- Testing policy:/d' \
    "$TARGET/.claude/CLAUDE.md" && rm -f "$TARGET/.claude/CLAUDE.md.bak"
  echo
  echo "Harness installed. Next steps:"
  echo "  1. Open $TARGET in its dev container (VS Code: 'Reopen in Container')"
  echo "     — or use the .claude/ harness without a container."
  echo "  2. Run /init in Claude Code. It fills gaps without overwriting: merges"
  echo "     the required .gitignore entries, scaffolds _planning/, renames the"
  echo "     container, asks commit/testing policy, and flags non-Node stacks"
  echo "     (recipes: .devcontainer/STACKS.md — the container ships Node-only)."
else
  echo
  echo "Done. Not touched: settings.local.json, .claude/logs/, _planning/."
  echo "If .devcontainer/ files changed, rebuild the target's container to apply."
fi
