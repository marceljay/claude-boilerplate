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
# copies no per-project choices: those live in the target's .claude/CUSTOM.md
# (## Harness settings), which this script creates as a stub if missing and
# otherwise never touches. Then reopen the project in its container
# and run /init to gap-fill (.gitignore security entries, _planning/,
# container rename, policies).
#
# REFRESH (target already has .claude/):
#   - MIRRORS the pure-harness dirs (.claude/{commands,skills,agents,hooks,
#     scripts}) and files (.claude/README.md, .devcontainer/STACKS.md,
#     .devcontainer/init-firewall.sh — the firewall LOGIC; the domain list
#     lives in allowed-domains.txt — and .devcontainer/claude-harness.zsh,
#     the shell shortcuts). In the mirrored dirs, the boilerplate's git
#     history decides each file: an outdated unedited copy is updated, a
#     locally edited one shows its diff and asks, a file this repo has
#     retired is listed (with the removing commit) and asked about, and a
#     file this repo never shipped is the project's own and is kept.
#   - SPLICES .devcontainer/Dockerfile: everything above its
#     `# ==== PROJECT LAYERS ====` marker is harness and is replaced with the
#     boilerplate's version; everything below (stack toolchains) is kept.
#     A target Dockerfile without the marker falls back to ask-first.
#   - For files that usually carry PER-PROJECT edits — .devcontainer/
#     allowed-domains.txt (firewall domains), devcontainer.json (container
#     name, stack features), .claude/CLAUDE.md (pure harness since
#     2026-09-08 — per-project lines belong in .claude/CUSTOM.md, and a
#     refresh moves any it finds there; answering y is normally right),
#     .claude/settings.json (permissions), .npmrc (registry/auth config),
#     .worktreeinclude (gitignored files copied into each worktree; the
#     harness allowlist plus any per-project `.env` lines) —
#     it shows the full diff and asks: y = overwrite, N = keep (default),
#     u = keep AND write the boilerplate version next to it as <file>.upstream
#     for a hand merge (delete the .upstream copy when done). Overwriting
#     devcontainer.json keeps the target's "name" and CLAUDE_SHORTCUT_FLAGS
#     values — the two single-value, always-per-project fields.
#   - INSTALL and REPLACE ask for the container name up front (default: the
#     directory name, or the old name in REPLACE) and write it into the
#     copied devcontainer.json, so /init has nothing left to rename.
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
# INSTALL-SHELL (--install-shell, no target): copies scripts/agent-sandbox.zsh — the
# host-side "run Claude in a container without VS Code" functions — to
# ~/.config/zsh/agent-sandbox.zsh (XDG_CONFIG_HOME honoured) and offers the one
# `source` line for ~/.zshrc. Also offered at the end of every sync. Host
# only (skipped inside the container); refuses a symlinked destination and
# never creates one — the installed copy must live where no agent can write
# (README "Run without VS Code"). agent-sandbox.zsh is never copied into targets.

set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
# The image sets DEVCONTAINER=true; captured here because the script reuses
# the name DEVCONTAINER for the devcontainer.json path further down.
IN_CONTAINER="${DEVCONTAINER:-}"

# --- Colour: only when stderr is a terminal and NO_COLOR is unset ----------
# Prompts are bold yellow on their own block; diffs get the usual +/- colours;
# status words are dimmed or highlighted by weight. Everything degrades to
# plain text when piped or under NO_COLOR (https://no-color.org).
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_RED=$'\033[31m' C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m' C_CYAN=$'\033[36m' C_OFF=$'\033[0m'
else
  C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_OFF=''
fi

# A unified diff with +/-/@@ coloured (headers = first two lines only, so a
# removed line that happens to start with "--" isn't mistaken for one).
# Never fails the script: diff exits 1 on differences by design.
show_diff() {
  diff -u "$1" "$2" | awk -v b="$C_BOLD" -v c="$C_CYAN" -v g="$C_GREEN" -v r="$C_RED" -v o="$C_OFF" '
    NR <= 2 && /^(\+\+\+|---) / { print b $0 o; next }
    /^@@/  { print c $0 o; next }
    /^\+/  { print g $0 o; next }
    /^-/   { print r $0 o; next }
           { print }' || true
}

# Status line: "<word>  <rest>" with the word coloured by what it means.
say() {
  local word="$1"; shift
  local c=""
  case "$word" in
    WARNING) c="$C_RED$C_BOLD" ;;
    overwrote|updated|spliced|moved|created|removed|copied) c="$C_YELLOW" ;;
    "in sync"|kept) c="$C_DIM" ;;
    differs|splicing|note) c="$C_CYAN" ;;
  esac
  printf '%s%-9s%s %s\n' "$c" "$word" "$C_OFF" "$*"
}

# Prompt block: blank line, a ruler, the question in bold yellow, so it can't
# be mistaken for a diff line. $1 = question, $2 = choices hint.
prompt_line() {
  printf '\n%s────────────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_OFF" >&2
  printf '%s%s?%s %s%s%s %s%s%s ' "$C_YELLOW" "$C_BOLD" "$C_OFF" "$C_BOLD" "$1" "$C_OFF" "$C_DIM" "$2" "$C_OFF" >&2
}

REPLACE=0
INSTALL_SHELL_ONLY=0
if [ "${1:-}" = "--replace" ]; then
  REPLACE=1
  shift
fi
if [ "${1:-}" = "--install-shell" ]; then
  INSTALL_SHELL_ONLY=1
  shift
fi
if [ "$INSTALL_SHELL_ONLY" = 1 ]; then
  if [ $# -ne 0 ] || [ "$REPLACE" = 1 ]; then
    echo "usage: $0 --install-shell   (no target; nothing else is synced)" >&2
    exit 1
  fi
elif [ $# -ne 1 ]; then
  echo "usage: $0 [--replace] <target-project-dir> | $0 --install-shell" >&2
  exit 1
fi
TARGET=""
if [ "$INSTALL_SHELL_ONLY" = 0 ]; then
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
fi

# Prompt helper: default No; piped/EOF input also means No.
ask() {
  local reply=""
  prompt_line "$1" "[y/N]"
  read -r reply || reply=n
  [ -t 0 ] || echo >&2   # piped input: end the prompt line ourselves
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
  prompt_line "$1" "[y = overwrite / N = keep / u = keep + write .upstream copy]"
  read -r reply || reply=n
  [ -t 0 ] || echo >&2   # piped input: end the prompt line ourselves
  case "$reply" in
    y | Y | yes | YES) echo overwrite ;;
    u | U) echo upstream ;;
    *) echo keep ;;
  esac
}

# --- agent-sandbox.zsh → ~/.config/zsh/agent-sandbox.zsh -----------------------------------
# sha256 of a file, host-portable (macOS ships shasum, Linux sha256sum).
file_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else echo "(no shasum/sha256sum on PATH)"; fi
}
AGENT_ZSH_SRC="$SRC/scripts/agent-sandbox.zsh"
AGENT_ZSH_DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
AGENT_ZSH_DEST="$AGENT_ZSH_DEST_DIR/agent-sandbox.zsh"
# The ~/.zshrc line. With the default location it uses the portable ~ form;
# with a custom XDG_CONFIG_HOME the resolved path, so the line works no
# matter where in .zshrc XDG_CONFIG_HOME gets set.
if [ "$AGENT_ZSH_DEST_DIR" = "$HOME/.config/zsh" ]; then
  AGENT_ZSH_SOURCE_LINE='[[ -r ~/.config/zsh/agent-sandbox.zsh ]] && source ~/.config/zsh/agent-sandbox.zsh'
else
  AGENT_ZSH_SOURCE_LINE="[[ -r $AGENT_ZSH_DEST ]] && source $AGENT_ZSH_DEST"
fi
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
# For a bash login shell (common on Linux): thin bash functions that run the
# zsh file in a zsh subprocess, so `agent-sandbox` works from bash without a port.
# AGENT_SANDBOX_TZ is read from the environment, so `export AGENT_SANDBOX_TZ=…` in .bashrc.
BASHRC="$HOME/.bashrc"
AGENT_BASH_SHIM_MARK='# agent-sandbox.zsh shim (sync-harness.sh --install-shell)'
agent_bash_shim() {
  cat <<EOF
$AGENT_BASH_SHIM_MARK
_agent_sandbox_zsh() { zsh -c 'source "\$1"; shift; "\$@"' zsh "$AGENT_ZSH_DEST" "\$@"; }
agent-sandbox() { _agent_sandbox_zsh agent-sandbox "\$@"; }
agent-sandbox-setup() { _agent_sandbox_zsh agent-sandbox-setup "\$@"; }
agent-sandbox-shell() { _agent_sandbox_zsh agent-sandbox-shell "\$@"; }
agent-sandbox-rebuild() { _agent_sandbox_zsh agent-sandbox-rebuild "\$@"; }
agent-sandbox-recreate() { _agent_sandbox_zsh agent-sandbox-recreate "\$@"; }
agent-sandbox-stop() { _agent_sandbox_zsh agent-sandbox-stop "\$@"; }
agent-sandbox-ports() { _agent_sandbox_zsh agent-sandbox-ports "\$@"; }
agent-sandbox-check() { _agent_sandbox_zsh agent-sandbox-check "\$@"; }
EOF
}

# Install or update the host-side agent-sandbox.zsh. Returns 0 unless something is
# wrong with the environment (symlink, syntax error, no zsh); declining is 0.
install_shell() {
  local version new_sha ts
  echo
  if [ "$IN_CONTAINER" = "true" ]; then
    say "note" "agent-sandbox.zsh: skipped — this runs inside the dev container; run it on the host:"
    echo "          scripts/sync-harness.sh --install-shell"
    return 0
  fi
  if [ ! -f "$AGENT_ZSH_SRC" ]; then
    say "WARNING" "scripts/agent-sandbox.zsh missing in $SRC — nothing to install"
    return 1
  fi
  if ! command -v zsh >/dev/null 2>&1; then
    say "WARNING" "no zsh on PATH — agent-sandbox.zsh is a zsh file; not offering the install"
    return 1
  fi
  if ! zsh -n "$AGENT_ZSH_SRC"; then
    say "WARNING" "scripts/agent-sandbox.zsh fails \`zsh -n\` — not offering the install"
    return 1
  fi
  # The file, its directory and the config root must all be real: a
  # ~/.config/zsh that is a symlink into a dotfiles repo is exactly the
  # agent-writable place the agent-sandbox.zsh header warns about.
  local link
  for link in "$AGENT_ZSH_DEST" "$AGENT_ZSH_DEST_DIR" "$(dirname "$AGENT_ZSH_DEST_DIR")"; do
    if [ -L "$link" ]; then
      say "WARNING" "$link is a symlink — refusing. agent-sandbox.zsh decides what the container"
      echo "          sees, so it must be a plain file in a real directory outside any folder"
      echo "          an agent can write to (a dotfiles repo you run Claude in counts)."
      echo "          Replace the symlink with a real directory/file, then re-run --install-shell."
      return 1
    fi
  done
  version=$(grep -m1 -E '^# AGENT_SANDBOX_VERSION=' "$AGENT_ZSH_SRC" | cut -d= -f2)
  # Before 2026-11-16 the file was agent.zsh and defined `agent`, `agent-rebuild`
  # etc. Both copies sourced from .zshrc would define both families, so offer
  # to remove the old file and rewrite its source line.
  local old_dest="$AGENT_ZSH_DEST_DIR/agent.zsh" old_line rc="$ZSHRC"
  if [ -e "$old_dest" ]; then
    say "note" "$old_dest is the pre-rename copy (commands were \`agent …\`, now \`agent-sandbox …\`)."
    if ask "Remove the old $old_dest?"; then
      rm -f "$old_dest" && say "removed" "$old_dest"
    else
      say "kept" "$old_dest — remove it yourself, or both command families stay defined"
    fi
    if [ "$AGENT_ZSH_DEST_DIR" = "$HOME/.config/zsh" ]; then
      old_line='[[ -r ~/.config/zsh/agent.zsh ]] && source ~/.config/zsh/agent.zsh'
    else
      old_line="[[ -r $old_dest ]] && source $old_dest"
    fi
    if [ -f "$rc" ] && grep -qF -- "$old_line" "$rc"; then
      say "note" "$rc still sources the old file:"
      echo "          $old_line"
      if ask "Replace that line with the agent-sandbox.zsh one?"; then
        cp -p "$rc" "$rc.bak-$(date +%Y%m%d-%H%M%S)"
        awk -v old="$old_line" -v new="$AGENT_ZSH_SOURCE_LINE" '$0 == old { print new; next } { print }' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
        say "copied" "$rc updated (backup kept beside it)"
      else
        say "kept" "$rc untouched — replace the line yourself"
      fi
    fi
  fi
  if [ -f "$BASHRC" ] && grep -qF -- '# agent.zsh shim (sync-harness.sh --install-shell)' "$BASHRC"; then
    say "WARNING" "$BASHRC has the pre-rename bash shim block (agent.zsh); remove it by hand, then accept the new block below."
  fi
  if [ ! -e "$AGENT_ZSH_DEST" ]; then
    say "note" "agent-sandbox.zsh ${version:-?} is not installed yet. It would be copied to:"
    echo "          $AGENT_ZSH_DEST   (mode 0644, a plain copy — not a symlink)"
    echo "          It defines agent-sandbox / agent-sandbox-rebuild / agent-sandbox-stop … (host-side zsh functions"
    echo "          that run Claude Code in a per-project Docker container without VS Code)."
    ask "Install agent-sandbox.zsh there?" || { say "kept" "agent-sandbox.zsh not installed"; return 0; }
  elif cmp -s "$AGENT_ZSH_SRC" "$AGENT_ZSH_DEST"; then
    say "in sync" "$AGENT_ZSH_DEST (agent-sandbox.zsh ${version:-?})"
    offer_zshrc_line
    return 0
  else
    say "differs" "$AGENT_ZSH_DEST vs scripts/agent-sandbox.zsh ${version:-?} (installed → boilerplate):"
    show_diff "$AGENT_ZSH_DEST" "$AGENT_ZSH_SRC"
    ask "Replace the installed agent-sandbox.zsh with this version?" || { say "kept" "$AGENT_ZSH_DEST"; return 0; }
    ts=$(date +%Y%m%d-%H%M%S)
    cp -p "$AGENT_ZSH_DEST" "$AGENT_ZSH_DEST.bak-$ts"
    say "copied" "backup → $AGENT_ZSH_DEST.bak-$ts"
  fi
  mkdir -p "$AGENT_ZSH_DEST_DIR"
  install -m 0644 "$AGENT_ZSH_SRC" "$AGENT_ZSH_DEST"
  new_sha=$(file_sha256 "$AGENT_ZSH_DEST")
  say "copied" "$AGENT_ZSH_DEST"
  echo "          AGENT_SANDBOX_VERSION=${version:-?}  sha256 $new_sha"
  offer_zshrc_line
}

# ~/.zshrc gets exactly one line, appended, only on a yes, only if absent.
# A bash login shell gets the shim block in ~/.bashrc instead, same rules.
offer_zshrc_line() {
  local rc="$ZSHRC"
  if [ "$(basename "${SHELL:-zsh}")" = bash ]; then
    offer_bashrc_shim
    return $?
  fi
  if [ -f "$rc" ] && grep -qF -- "$AGENT_ZSH_SOURCE_LINE" "$rc"; then
    say "in sync" "$rc already sources agent-sandbox.zsh"
    return 0
  fi
  say "note" "$rc does not source it yet. The line to add:"
  echo "          $AGENT_ZSH_SOURCE_LINE"
  if ask "Append that line to $rc?"; then
    printf '\n%s\n' "$AGENT_ZSH_SOURCE_LINE" >> "$rc"
    say "copied" "appended to $rc — open a new shell (or \`source $rc\`)"
  else
    say "kept" "$rc untouched — add the line yourself to use \`agent-sandbox\`"
  fi
}

offer_bashrc_shim() {
  if [ -f "$BASHRC" ] && grep -qF -- "$AGENT_BASH_SHIM_MARK" "$BASHRC"; then
    say "in sync" "$BASHRC already has the agent shim"
    return 0
  fi
  say "note" "your login shell is bash. agent-sandbox.zsh is a zsh file; this block in $BASHRC runs it through zsh:"
  agent_bash_shim | sed 's/^/          /'
  if ask "Append that block to $BASHRC?"; then
    { printf '\n'; agent_bash_shim; } >> "$BASHRC"
    say "copied" "appended to $BASHRC — open a new shell (or \`source $BASHRC\`)"
  else
    say "kept" "$BASHRC untouched — add the block yourself to use \`agent-sandbox\` from bash"
  fi
}

if [ "$INSTALL_SHELL_ONLY" = 1 ]; then
  install_shell
  exit $?
fi

# --- devcontainer.json field helpers ----------------------------------------
# Read / set a string value on a `"key": "value"` line (first match). Plain
# awk/sed so it runs on a macOS host too; JSONC comments are left untouched.
json_line_value() {
  # Always succeeds (empty output when the key is absent) — callers assign
  # the result under set -e/pipefail, so a missing key must not be an error.
  { grep -m1 -E "^[[:space:]]*\"$2\":" "$1" 2>/dev/null || true; } \
    | sed -E 's/^[^:]*:[[:space:]]*"([^"]*)".*$/\1/'
}
set_json_line_value() {
  local tmp; tmp=$(mktemp)
  awk -v key="$2" -v val="$3" '
    !done && $0 ~ ("^[[:space:]]*\"" key "\":") {
      match($0, /^[[:space:]]*"[^"]*":[[:space:]]*/)
      pre = substr($0, 1, RLENGTH); rest = substr($0, RLENGTH + 1)
      sub(/^"[^"]*"/, "", rest)
      gsub(/"/, "\\\"", val)
      print pre "\"" val "\"" rest; done = 1; next
    }
    { print }' "$1" > "$tmp" && cat "$tmp" > "$1"
  rm -f "$tmp"
}
DEVCONTAINER=.devcontainer/devcontainer.json
DEFAULT_CONTAINER_NAME="Claude Boilerplate Repo"

# A Dockerfile whose FROM line changed means a different Node (or distro):
# native modules built against the old one fail to load until rebuilt, and
# under the repo's .npmrc a plain `npm rebuild` is a silent no-op. Say so.
from_line() { grep -m1 -E '^FROM ' "$1" 2>/dev/null || true; }
warn_if_base_image_changed() {   # old-content-file new-content-file
  local a b; a=$(from_line "$1"); b=$(from_line "$2")
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]; then
    echo "BASE_IMAGE_CHANGED: '$a' -> '$b'. After rebuilding the container, rebuild native"
    echo "          modules: see .devcontainer/STACKS.md §Supply-chain hardening (the "Native modules" paragraph) (approve once, then"
    echo "          'npm rebuild --ignore-scripts=false' — a plain 'npm rebuild' does nothing)."
  fi
}
# Upstream devcontainer.json with the target's own "name" and
# CLAUDE_SHORTCUT_FLAGS substituted — what an overwrite would actually
# produce. Written to the file named by $1.
devcontainer_upstream_with_target_fields() {
  local k v; cp "$SRC/$DEVCONTAINER" "$1"
  for k in name CLAUDE_SHORTCUT_FLAGS; do
    v=$(json_line_value "$TARGET/$DEVCONTAINER" "$k")
    if [ -n "$v" ]; then set_json_line_value "$1" "$k" "$v"; fi
  done
}
# JSONC minus comments and all whitespace: the target's copy is usually
# reformatted by the editor (Prettier folds runArgs onto one line, etc.), and
# that is not a difference worth a prompt.
jsonc_squash() { sed 's|^[[:space:]]*//.*$||' "$1" | tr -d ' \t\r\n'; }
# True when nothing but formatting and the two per-project values differs.
devcontainer_in_sync_modulo_fields() {
  local tmp rc; tmp=$(mktemp); devcontainer_upstream_with_target_fields "$tmp"
  [ "$(jsonc_squash "$tmp")" = "$(jsonc_squash "$TARGET/$DEVCONTAINER")" ]; rc=$?
  rm -f "$tmp"; return $rc
}


ADOPT=0
if [ "$REPLACE" = 1 ] && { [ -d "$TARGET/.claude" ] || [ -d "$TARGET/.devcontainer" ]; }; then
  old_dirs=""
  [ -d "$TARGET/.claude" ] && old_dirs=".claude"
  [ -d "$TARGET/.devcontainer" ] && old_dirs="$old_dirs .devcontainer"
  backup="harness-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  OLD_CONTAINER_NAME=$(json_line_value "$TARGET/.devcontainer/devcontainer.json" name 2>/dev/null || true)
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
# Each file is classified against the boilerplate's git history, so neither
# a local edit nor a project's own file is lost without asking:
#   - same content as here             → nothing to do
#   - matches a past boilerplate version → outdated copy; updated silently
#   - matches no boilerplate version    → edited in the target; diff + ask
#   - only in the target, path never shipped here → project's own; kept
#   - only in the target, path shipped here once  → retired upstream; ask
# Without git history (no .git, or a shallow clone) every file that differs
# counts as edited and every target-only file is asked about.
MIRROR_DIRS=".claude/commands .claude/skills .claude/agents .claude/hooks .claude/scripts"

HAVE_HISTORY=0
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 &&
   [ "$(git -C "$SRC" rev-parse --is-shallow-repository 2>/dev/null)" = false ]; then
  HAVE_HISTORY=1
fi

# Relative file list of a dir, minus caches/cruft. Runs in a subshell (cd).
list_files() {
  (cd "$1" && find . -type f ! -path '*__pycache__*' ! -name '.DS_Store' | sed 's|^\./||' | sort)
}

# Did the boilerplate ever ship this path ($1, relative to $SRC)?
shipped_upstream() {
  [ "$HAVE_HISTORY" = 1 ] && [ -n "$(git -C "$SRC" log -1 --format=%h -- "$1" 2>/dev/null)" ]
}

# Is the target file $2 byte-identical to some committed version of $1?
matches_past_version() {
  [ "$HAVE_HISTORY" = 1 ] || return 1
  local blob c
  blob=$(git -C "$SRC" hash-object -- "$2") || return 1
  while IFS= read -r c; do
    [ "$(git -C "$SRC" rev-parse -q --verify "$c:$1" 2>/dev/null)" = "$blob" ] && return 0
  done < <(git -C "$SRC" log --format=%H -- "$1" 2>/dev/null)
  return 1
}

for d in $MIRROR_DIRS; do
  [ -d "$SRC/$d" ] || continue
  mkdir -p "$TARGET/$d"
  n_new=0 n_updated=0 n_kept=0

  # Files only in the target. fd 3 keeps stdin free for the prompts.
  retired="" own=""
  while IFS= read -r p <&3; do
    if shipped_upstream "$d/$p"; then
      note=$(git -C "$SRC" log -1 --diff-filter=D --format='removed in %h (%ad)' --date=short -- "$d/$p")
      matches_past_version "$d/$p" "$TARGET/$d/$p" || note="$note, EDITED in target"
      retired="$retired$p"$'\t'"$note"$'\n'
    else
      own="$own$p"$'\n'
    fi
  done 3< <(comm -13 <(list_files "$SRC/$d") <(list_files "$TARGET/$d"))

  if [ -n "$own" ]; then
    if [ "$HAVE_HISTORY" = 1 ]; then
      printf '%s' "$own" | while IFS= read -r p; do say kept "$d/$p (project's own file)"; done
    else
      echo "$d: target-only files (no boilerplate git history to tell retired from own):"
      printf '%s' "$own" | sed 's/^/    /'
      if ask "  Delete them in the target?"; then
        printf '%s' "$own" | while IFS= read -r p; do
          rm -f -- "$TARGET/$d/$p"
          (cd "$TARGET/$d" && rmdir -p "$(dirname "$p")" 2>/dev/null) || true
          say removed "$d/$p"
        done
      fi
    fi
  fi
  if [ -n "$retired" ]; then
    echo "$d: files the boilerplate has retired:"
    printf '%s' "$retired" | awk -F'\t' '{ printf "    %s  (%s)\n", $1, $2 }'
    if ask "  Delete them in the target?"; then
      printf '%s' "$retired" | cut -f1 | while IFS= read -r p; do
        rm -f -- "$TARGET/$d/$p"
        (cd "$TARGET/$d" && rmdir -p "$(dirname "$p")" 2>/dev/null) || true
        say removed "$d/$p"
      done
    fi
  fi

  # Files the boilerplate ships: copy new ones, update outdated ones, ask
  # about edited ones.
  while IFS= read -r p <&3; do
    src="$SRC/$d/$p" dst="$TARGET/$d/$p"
    if [ ! -e "$dst" ]; then
      mkdir -p "$(dirname "$dst")"; cp -p "$src" "$dst"; n_new=$((n_new + 1))
    elif cmp -s "$src" "$dst"; then
      [ -x "$src" ] && [ ! -x "$dst" ] && chmod +x "$dst"
    elif matches_past_version "$d/$p" "$dst"; then
      cp -p "$src" "$dst"; n_updated=$((n_updated + 1))
    else
      echo
      say differs "$d/$p (edited in target — matches no boilerplate version)"
      show_diff "$dst" "$src"
      case "$(ask3 "Overwrite $d/$p with the boilerplate version?")" in
        overwrite) cp -p "$src" "$dst"; say overwrote "$d/$p"; n_updated=$((n_updated + 1)) ;;
        upstream)  cp -p "$src" "$dst.upstream"; n_kept=$((n_kept + 1))
                   say kept "$d/$p (target version); boilerplate copy written to $p.upstream" ;;
        *)         say kept "$d/$p (target version)"; n_kept=$((n_kept + 1)) ;;
      esac
    fi
  done 3< <(list_files "$SRC/$d")

  if [ $((n_new + n_updated + n_kept)) -eq 0 ]; then
    say "in sync" "$d"
  else
    say updated "$d ($n_new new, $n_updated updated, $n_kept kept with local edits)"
  fi
done

# init-firewall.sh is mirrored because it is pure logic now — the per-project
# domain list lives in allowed-domains.txt (ask-first, below). cp -p keeps
# its exec bit.
for f in .claude/README.md .devcontainer/STACKS.md .devcontainer/init-firewall.sh .devcontainer/initialize.sh .devcontainer/claude-harness.zsh; do
  [ -f "$SRC/$f" ] || continue
  mkdir -p "$TARGET/$(dirname "$f")"
  cp -p "$SRC/$f" "$TARGET/$f"
  say "copied" "$f"
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
  if [ "$f" = "$DEVCONTAINER" ]; then
    # Diff against what an overwrite would produce: the target's name and
    # flags already in place, so only real upstream changes show.
    local want; want=$(mktemp); devcontainer_upstream_with_target_fields "$want"
    say "differs" "$f (your \"name\" and CLAUDE_SHORTCUT_FLAGS are kept on overwrite;"
    echo "          whitespace-only differences are ignored — this diff has real changes)"
    show_diff "$TARGET/$f" "$want"
    rm -f "$want"
  else
    say "differs" "$f (target may hold per-project edits)"
    show_diff "$TARGET/$f" "$SRC/$f"
  fi
  case "$(ask3 "Overwrite $f with the boilerplate version?")" in
    overwrite)
      [ "$f" = "$DOCKERFILE" ] && warn_if_base_image_changed "$TARGET/$f" "$SRC/$f"
      if [ "$f" = "$DEVCONTAINER" ]; then
        # Carry the per-project single values over; everything else is upstream.
        local keep_name keep_flags k
        keep_name=$(json_line_value "$TARGET/$f" name)
        keep_flags=$(json_line_value "$TARGET/$f" CLAUDE_SHORTCUT_FLAGS)
        cp -p "$SRC/$f" "$TARGET/$f"
        for k in name CLAUDE_SHORTCUT_FLAGS; do
          local v; v=$([ "$k" = name ] && echo "$keep_name" || echo "$keep_flags")
          if [ -n "$v" ] && [ "$(json_line_value "$TARGET/$f" "$k")" != "$v" ]; then
            set_json_line_value "$TARGET/$f" "$k" "$v"
            say "overwrote" "$f (kept \"$k\": \"$v\")"
          fi
        done
        say "overwrote" "$f"
      else
        cp -p "$SRC/$f" "$TARGET/$f"
        say "overwrote" "$f"
      fi ;;
    upstream)
      cp -p "$SRC/$f" "$TARGET/$f.upstream"
      say "kept" "$f (target version); boilerplate copy written to $f.upstream"
      echo "          — merge by hand, then delete the .upstream file" ;;
    *)
      say kept "$f (target version)" ;;
  esac
}

echo
if [ -f "$SRC/$DOCKERFILE" ]; then
  if [ ! -f "$TARGET/$DOCKERFILE" ]; then
    mkdir -p "$TARGET/.devcontainer"
    cp -p "$SRC/$DOCKERFILE" "$TARGET/$DOCKERFILE"
    say "copied" "$DOCKERFILE (was missing in target)"
  elif cmp -s "$SRC/$DOCKERFILE" "$TARGET/$DOCKERFILE"; then
    say "in sync" "$DOCKERFILE"
  elif has_marker "$SRC/$DOCKERFILE" && has_marker "$TARGET/$DOCKERFILE"; then
    spliced=$(mktemp)
    { dockerfile_head "$SRC/$DOCKERFILE"; dockerfile_tail "$TARGET/$DOCKERFILE"; } > "$spliced"
    if cmp -s "$spliced" "$TARGET/$DOCKERFILE"; then
      say "in sync" "$DOCKERFILE (harness section; project layers untouched)"
    else
      echo
      say "splicing" "$DOCKERFILE — harness section refreshed, project layers below the marker kept:"
      show_diff "$TARGET/$DOCKERFILE" "$spliced"
      warn_if_base_image_changed "$TARGET/$DOCKERFILE" "$spliced"
      cat "$spliced" > "$TARGET/$DOCKERFILE"
      say "spliced" "$DOCKERFILE (review with git diff; rebuild the container to apply)"
    fi
    rm -f "$spliced"
  else
    echo
    say "note" "$DOCKERFILE: target has no '$DOCKERFILE_MARKER' marker line (at column 1),"
    echo "          so it can't be spliced. Answer y if it has no project-specific layers; otherwise u,"
    echo "          then move your layers BELOW the marker in the .upstream copy and"
    echo "          rename it over the target — future syncs then splice automatically."
    ask_first "$DOCKERFILE"
  fi
fi

# --- 2b. .claude/CUSTOM.md: the per-project file this script never syncs --
# .claude/CLAUDE.md imports it (@CUSTOM.md), so it must exist; create the
# stub when missing. Then move any per-project lines that older copies
# (before 2026-09-08) still hold inside .claude/CLAUDE.md — the file this
# script overwrites — so "overwrite" can't lose them.
CUSTOM="$TARGET/.claude/CUSTOM.md"
CUSTOM_STUB='# Project customizations

Per-project choices and deviations the synced `.claude/CLAUDE.md` defers to.
`sync-harness.sh` never touches this file; `/init` fills it in. Where a line
here contradicts `.claude/CLAUDE.md`, this file wins.

## Harness settings

<!-- - Harness: committed | local
     - STATUS.md: private | public [path]
     - Commit policy: on-request | milestones | periodic
     - Testing policy: on-request | tests-with-features | tdd
     - Commit session links: off | on
     - Review page: off | on
     - Changelog: fragments | inline -->

## Deviations

<!-- One line each, e.g. "STATUS.md is tracked at ./STATUS.md so contributors
     see it" or ".claude/ is gitignored here — personal tooling, not shared". -->
'
if [ ! -f "$CUSTOM" ]; then
  mkdir -p "$TARGET/.claude"
  printf '%s' "$CUSTOM_STUB" > "$CUSTOM"
  say "created" ".claude/CUSTOM.md (stub — /init fills it; never synced)"
fi
BATON_RE='^- (Harness|STATUS\.md|Commit policy|Testing policy|Commit session links|Review page|Changelog):'
if [ -f "$TARGET/.claude/CLAUDE.md" ] && grep -Eq "$BATON_RE" "$TARGET/.claude/CLAUDE.md"; then
  moved="$(grep -E "$BATON_RE" "$TARGET/.claude/CLAUDE.md" | sed -E 's/ \(this repo\)\.?$//')"
  grep -q '^## Harness settings' "$CUSTOM" || printf '\n## Harness settings\n\n' >> "$CUSTOM"
  # Insert each line (whose key CUSTOM.md lacks) right after the heading.
  printf '%s\n' "$moved" | while IFS= read -r line; do
    key="${line%%:*}"
    grep -q "^$key:" "$CUSTOM" && continue
    awk -v l="$line" '{print} /^## Harness settings$/ {getline; print; print l}' "$CUSTOM" > "$CUSTOM.tmp" \
      && mv "$CUSTOM.tmp" "$CUSTOM"
  done
  sed -i.bak -E "/$BATON_RE/d" "$TARGET/.claude/CLAUDE.md" && rm -f "$TARGET/.claude/CLAUDE.md.bak"
  say "moved" "per-project lines from .claude/CLAUDE.md to .claude/CUSTOM.md:"
  printf '%s\n' "$moved" | sed 's/^/            /'
fi

# --- 2c. Per-project files copied only when missing, never overwritten ------
# .devcontainer/agent-sandbox-ports: the ports scripts/agent-sandbox.zsh publishes for the
# target's container; .devcontainer/agent-sandbox-nested-repos: nested repositories
# agent-sandbox.zsh accepts under the project. Pure per-project data (the
# boilerplate's copies are the documented empty templates), so a target's
# lists are never touched.
COPY_IF_MISSING=".devcontainer/agent-sandbox-ports .devcontainer/agent-sandbox-nested-repos"
for f in $COPY_IF_MISSING; do
  [ -f "$SRC/$f" ] || continue
  # Pre-2026-11-16 name (agent-ports, agent-nested-repos): rename the target's
  # copy, which keeps its per-project lines; never overwrite an existing new one.
  old="$TARGET/$(dirname "$f")/$(basename "$f" | sed 's/^agent-sandbox-/agent-/')"
  if [ -f "$old" ]; then
    if [ -f "$TARGET/$f" ]; then
      say "WARNING" "$f and the old $(basename "$old") both exist — merge by hand, then delete the old one"
    else
      mv "$old" "$TARGET/$f" && say "renamed" "$(basename "$old") → $f (old name from before the agent-sandbox rename)"
    fi
  fi
  if [ ! -f "$TARGET/$f" ]; then
    mkdir -p "$TARGET/$(dirname "$f")"
    cp -p "$SRC/$f" "$TARGET/$f"
    say "copied" "$f (was missing in target; never overwritten afterwards)"
  else
    say "kept" "$f (per-project)"
  fi
done

# --- 3. Ask-first files (commonly hold per-project edits) ------------------
ASK_FILES=".devcontainer/allowed-domains.txt .devcontainer/devcontainer.json .claude/CLAUDE.md .claude/settings.json .npmrc .worktreeinclude"

for f in $ASK_FILES; do
  [ -f "$SRC/$f" ] || continue
  if [ ! -f "$TARGET/$f" ]; then
    mkdir -p "$TARGET/$(dirname "$f")"
    cp -p "$SRC/$f" "$TARGET/$f"
    say "copied" "$f (was missing in target)"
  elif cmp -s "$SRC/$f" "$TARGET/$f"; then
    say "in sync" "$f"
  elif [ "$f" = "$DEVCONTAINER" ] && devcontainer_in_sync_modulo_fields; then
    say "in sync" "$f (name / CLAUDE_SHORTCUT_FLAGS are the target's own)"
  else
    ask_first "$f"
  fi
done

# devcontainer.json is ask-first, so a kept target copy may predate the
# host-side opt-in and the read-only mounts of the "Reopen in Container"
# path. initialize.sh was copied above; without the wiring it never runs.
if [ -f "$TARGET/$DEVCONTAINER" ] && ! grep -q 'initialize.sh' "$TARGET/$DEVCONTAINER"; then
  say "WARNING" "$DEVCONTAINER has no initializeCommand for .devcontainer/initialize.sh"
  echo "          copy the \"initializeCommand\" block and the six \"mounts\" bind lines from"
  echo "          $SRC/$DEVCONTAINER, or VS Code reopen runs without the opt-in and the read-only mounts."
fi

# --- 3b. Hook files that reached the target but aren't wired ---------------
# settings.json is ask-first and usually kept, so a hook added upstream lands
# in .claude/hooks/ without a PreToolUse/SessionStart entry and silently never
# runs. Say so; the fix is one copied block, not the whole file.
if [ -f "$TARGET/.claude/settings.json" ]; then
  unwired=""
  for h in "$TARGET"/.claude/hooks/*.py "$TARGET"/.claude/hooks/*.sh; do
    [ -f "$h" ] || continue
    grep -q "$(basename "$h")" "$TARGET/.claude/settings.json" || unwired="$unwired $(basename "$h")"
  done
  if [ -n "$unwired" ]; then
    say "WARNING" "hook file(s) present but not wired in .claude/settings.json:$unwired"
    echo "          copy their entries from $SRC/.claude/settings.json (\"hooks\") into yours, or they never run."
  fi
fi

# --- 4. Install-mode fixups -------------------------------------------------
if [ "$ADOPT" = 1 ]; then
  # The copied CLAUDE.md records THIS repo's per-project choices — strip them
  # so /init asks the adopting project fresh.
  sed -i.bak -e '/^- Commit policy:/d' -e '/^- Testing policy:/d' \
    -e '/^- Commit session links:/d' -e '/^- Review page:/d' -e '/^- Changelog:/d' \
    -e '/^- Harness:/d' -e '/^- STATUS\.md:/d' \
    "$TARGET/.claude/CLAUDE.md" && rm -f "$TARGET/.claude/CLAUDE.md.bak"

  # Container name: it labels the container in Docker/VS Code, and the
  # boilerplate default is what the first-run hook keys off — so set it now
  # rather than shipping a copy that still says "Claude Boilerplate Repo".
  if [ -f "$TARGET/$DEVCONTAINER" ] && [ "$(json_line_value "$TARGET/$DEVCONTAINER" name)" = "$DEFAULT_CONTAINER_NAME" ]; then
    default_name="${OLD_CONTAINER_NAME:-}"
    [ -n "$default_name" ] && [ "$default_name" != "$DEFAULT_CONTAINER_NAME" ] || default_name="$(basename "$TARGET")"
    prompt_line "Dev container name" "[$default_name]"
    read -r new_name || new_name=""
    [ -t 0 ] || echo
    [ -n "$new_name" ] || new_name="$default_name"
    set_json_line_value "$TARGET/$DEVCONTAINER" name "$new_name"
    echo "named     $DEVCONTAINER \"$new_name\""
  fi
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

# --- 5. Host-side agent-sandbox.zsh (not part of the target; lives in ~/.config) ----
install_shell || true
