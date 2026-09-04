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
# strips this repo's recorded per-project choice lines (commit/testing
# policy, Harness:, STATUS.md:) from the copied CLAUDE.md so /init asks fresh. Then reopen the project in its container
# and run /init to gap-fill (.gitignore security entries, _planning/,
# container rename, policies).
#
# REFRESH (target already has .claude/):
#   - MIRRORS the pure-harness dirs (.claude/{commands,skills,agents,hooks,
#     scripts}) and files (.claude/README.md, .devcontainer/STACKS.md,
#     .devcontainer/init-firewall.sh — the firewall LOGIC; the domain list
#     lives in allowed-domains.txt — and .devcontainer/claude-harness.zsh,
#     the shell shortcuts). Mirroring also deletes files this repo
#     has since retired (e.g. removed commands) — it lists those and asks
#     first.
#   - SPLICES .devcontainer/Dockerfile: everything above its
#     `# ==== PROJECT LAYERS ====` marker is harness and is replaced with the
#     boilerplate's version; everything below (stack toolchains) is kept.
#     A target Dockerfile without the marker falls back to ask-first.
#   - For files that usually carry PER-PROJECT edits — .devcontainer/
#     allowed-domains.txt (firewall domains), devcontainer.json (container
#     name, stack features), .claude/CLAUDE.md (commit/testing policy),
#     .claude/settings.json (permissions), .npmrc (registry/auth config) —
#     it shows the full diff and asks: y = overwrite, N = keep (default),
#     u = keep AND write the boilerplate version next to it as <file>.upstream
#     for a hand merge (delete the .upstream copy when done).
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

# Three-way prompt for ask-first files. Prints one of: overwrite, upstream,
# keep — on stdout, for $(...) capture, so the prompt itself goes to stderr.
# Default (and piped/EOF input) is keep.
ask3() {
  local reply=""
  printf '%s [y=overwrite / N=keep / u=keep + write .upstream copy] ' "$1" >&2
  read -r reply || reply=n
  case "$reply" in
    y | Y | yes | YES) echo overwrite ;;
    u | U) echo upstream ;;
    *) echo keep ;;
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

# init-firewall.sh is mirrored because it is pure logic now — the per-project
# domain list lives in allowed-domains.txt (ask-first, below). cp -p keeps
# its exec bit.
for f in .claude/README.md .devcontainer/STACKS.md .devcontainer/init-firewall.sh .devcontainer/claude-harness.zsh; do
  [ -f "$SRC/$f" ] || continue
  mkdir -p "$TARGET/$(dirname "$f")"
  cp -p "$SRC/$f" "$TARGET/$f"
  echo "copied    $f"
done

# --- 2. Dockerfile: splice at the project-layers marker ---------------------
# Above the marker = harness (replaced); below = the project's own layers
# (kept). Matched on the fixed prefix so trailing commentary can change.
DOCKERFILE=.devcontainer/Dockerfile
DOCKERFILE_MARKER='# ==== PROJECT LAYERS ===='

# Line number of the first marker line (must start at column 1 — an indented
# or otherwise mangled marker deliberately does NOT count, so such a target
# falls back to ask-first instead of being mis-spliced). Empty if absent.
marker_line() { grep -n -m1 -F -- "$DOCKERFILE_MARKER" "$1" | grep "^[0-9]*:$DOCKERFILE_MARKER" | cut -d: -f1; }
has_marker() { [ -n "$(marker_line "$1")" ]; }
# Upstream part: through the marker line. Project part: everything after it.
dockerfile_head() { head -n "$(marker_line "$1")" "$1"; }
dockerfile_tail() { tail -n +"$(( $(marker_line "$1") + 1 ))" "$1"; }

# Ask-first handling shared by the fallback below and step 3.
ask_first() {
  local f="$1"
  echo
  echo "differs   $f (target may hold per-project edits)"
  diff -u "$TARGET/$f" "$SRC/$f" || true
  case "$(ask3 "  $f:")" in
    overwrite)
      cp -p "$SRC/$f" "$TARGET/$f"
      echo "overwrote $f" ;;
    upstream)
      cp -p "$SRC/$f" "$TARGET/$f.upstream"
      echo "kept      $f (target version); boilerplate copy written to $f.upstream"
      echo "          — merge by hand, then delete the .upstream file" ;;
    *)
      echo "kept      $f (target version)" ;;
  esac
}

echo
if [ -f "$SRC/$DOCKERFILE" ]; then
  if [ ! -f "$TARGET/$DOCKERFILE" ]; then
    mkdir -p "$TARGET/.devcontainer"
    cp -p "$SRC/$DOCKERFILE" "$TARGET/$DOCKERFILE"
    echo "copied    $DOCKERFILE (was missing in target)"
  elif cmp -s "$SRC/$DOCKERFILE" "$TARGET/$DOCKERFILE"; then
    echo "in sync   $DOCKERFILE"
  elif has_marker "$SRC/$DOCKERFILE" && has_marker "$TARGET/$DOCKERFILE"; then
    spliced=$(mktemp)
    { dockerfile_head "$SRC/$DOCKERFILE"; dockerfile_tail "$TARGET/$DOCKERFILE"; } > "$spliced"
    if cmp -s "$spliced" "$TARGET/$DOCKERFILE"; then
      echo "in sync   $DOCKERFILE (harness section; project layers untouched)"
    else
      echo
      echo "splicing  $DOCKERFILE — harness section refreshed, project layers below the marker kept:"
      diff -u "$TARGET/$DOCKERFILE" "$spliced" || true
      cat "$spliced" > "$TARGET/$DOCKERFILE"
      echo "spliced   $DOCKERFILE (review with git diff; rebuild the container to apply)"
    fi
    rm -f "$spliced"
  else
    echo
    echo "note      $DOCKERFILE: target has no '$DOCKERFILE_MARKER' marker line (at column 1),"
    echo "          so it can't be spliced. Answer y if it has no project-specific layers; otherwise u,"
    echo "          then move your layers BELOW the marker in the .upstream copy and"
    echo "          rename it over the target — future syncs then splice automatically."
    ask_first "$DOCKERFILE"
  fi
fi

# --- 3. Ask-first files (commonly hold per-project edits) ------------------
ASK_FILES=".devcontainer/allowed-domains.txt .devcontainer/devcontainer.json .claude/CLAUDE.md .claude/settings.json .npmrc"

for f in $ASK_FILES; do
  [ -f "$SRC/$f" ] || continue
  if [ ! -f "$TARGET/$f" ]; then
    mkdir -p "$TARGET/$(dirname "$f")"
    cp -p "$SRC/$f" "$TARGET/$f"
    echo "copied    $f (was missing in target)"
  elif cmp -s "$SRC/$f" "$TARGET/$f"; then
    echo "in sync   $f"
  else
    ask_first "$f"
  fi
done

# --- 4. Install-mode fixups -------------------------------------------------
if [ "$ADOPT" = 1 ]; then
  # The copied CLAUDE.md records THIS repo's per-project choices — strip them
  # so /init asks the adopting project fresh.
  sed -i.bak -e '/^- Commit policy:/d' -e '/^- Testing policy:/d' \
    -e '/^- Harness:/d' -e '/^- STATUS\.md:/d' \
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
