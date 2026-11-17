#!/usr/bin/env bash
# Tests for .devcontainer/initialize.sh, the host-side step of the VS Code
# "Reopen in Container" path. No Docker, no VS Code: each case builds a fake
# repository in a temp dir, points HOME/XDG_CONFIG_HOME at a temp home (never
# the real one) and runs the script with `sh`.
#
#   bash scripts/tests/initialize_sh_test.sh

set -u

here=$(cd "$(dirname "$0")" && pwd)
script=$here/../../.devcontainer/initialize.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME=$tmp/home
export XDG_CONFIG_HOME=$tmp/home/.config
mkdir -p "$HOME"
unset AGENT_SANDBOX_ALLOW_VSCODE

# A fake git on PATH: the script must never call it (a planted
# core.fsmonitor would run). It leaves a marker if it is ever executed.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/git" <<EOF
#!/bin/sh
touch "$tmp/GIT_WAS_RUN"
exit 0
EOF
chmod +x "$tmp/bin/git"
export PATH=$tmp/bin:$PATH

pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "FAIL: $*" >&2; }
check() { # check <description> <command...>
  local d=$1; shift
  if "$@"; then ok; else bad "$d"; fi
}

fresh_repo() { # fresh_repo <name> -> prints the dir
  local d=$tmp/$1
  rm -rf "$d"
  mkdir -p "$d/.git/hooks"
  : > "$d/.git/config"
  printf '%s\n' "$d"
}

run() { # run <dir> -> rc; stdout/stderr in $out
  out=$(sh "$script" "$1" 2>&1)
  return $?
}

# 1. No opt-in: refused, nothing created, the message names both switches.
d=$(fresh_repo a)
run "$d"; rc=$?
check "no opt-in exits 1" test "$rc" -eq 1
check "no opt-in names the env var" grep -q AGENT_SANDBOX_ALLOW_VSCODE <<<"$out"
check "no opt-in names the marker" grep -q agent-sandbox-allow-vscode <<<"$out"
check "no opt-in creates no commondir" test ! -e "$d/.git/commondir"
check "no opt-in creates no .vscode" test ! -e "$d/.vscode"

# 2. Env opt-in on a fresh repo: placeholder and .vscode created.
d=$(fresh_repo b)
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check "env opt-in exits 0" test "$rc" -eq 0
check "placeholder holds '.' without newline" test "$(wc -c < "$d/.git/commondir" | tr -d ' ')" = 1
check "placeholder content is '.'" test "$(cat "$d/.git/commondir")" = .
check ".vscode created" test -d "$d/.vscode"
check "creation is reported" grep -q 'created' <<<"$out"

# 3. Second run is idempotent and quiet.
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check "rerun exits 0" test "$rc" -eq 0
check "rerun prints nothing" test -z "$out"
check "rerun keeps the placeholder" test "$(cat "$d/.git/commondir")" = .

# 4. Marker-file opt-in, no env var.
mkdir -p "$XDG_CONFIG_HOME/zsh"; : > "$XDG_CONFIG_HOME/zsh/agent-sandbox-allow-vscode"
d=$(fresh_repo c)
run "$d"; rc=$?
check "marker opt-in exits 0" test "$rc" -eq 0
rm "$XDG_CONFIG_HOME/zsh/agent-sandbox-allow-vscode"

# 5. AGENT_SANDBOX_ALLOW_VSCODE must be exactly 1.
d=$(fresh_repo d)
AGENT_SANDBOX_ALLOW_VSCODE=yes run "$d"; rc=$?
check "AGENT_SANDBOX_ALLOW_VSCODE=yes is not an opt-in" test "$rc" -eq 1

# 6. .git is a file (linked worktree): refused.
d=$tmp/e; rm -rf "$d"; mkdir -p "$d"; echo 'gitdir: /x' > "$d/.git"
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check ".git file refused" test "$rc" -eq 1
check ".git file message names the main worktree" grep -q 'main worktree' <<<"$out"

# 7. Missing hooks dir: refused.
d=$(fresh_repo f); rmdir "$d/.git/hooks"
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check "missing hooks refused" test "$rc" -eq 1

# 8. Planted commondir redirect: refused with DANGER, left untouched.
d=$(fresh_repo g); printf '../x' > "$d/.git/commondir"
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check "redirect refused" test "$rc" -eq 1
check "redirect message says DANGER" grep -q DANGER <<<"$out"
check "redirect file untouched" test "$(cat "$d/.git/commondir")" = ../x
check "redirect: no .vscode created" test ! -e "$d/.vscode"

# 9. Placeholder with a trailing newline is not accepted either.
d=$(fresh_repo h); printf '.\n' > "$d/.git/commondir"
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check "placeholder with newline refused" test "$rc" -eq 1

# 10. Linked worktree commondirs: ../.. passes, anything else is refused.
d=$(fresh_repo i); mkdir -p "$d/.git/worktrees/t1" "$d/.git/worktrees/t2"
printf '../..' > "$d/.git/worktrees/t1/commondir"
printf '../..' > "$d/.git/worktrees/t2/commondir"
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check "worktree commondirs ../.. pass" test "$rc" -eq 0
printf '../../../x' > "$d/.git/worktrees/t2/commondir"
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check "worktree commondir redirect refused" test "$rc" -eq 1
check "worktree message names the file" grep -q 'worktrees/t2/commondir' <<<"$out"

# 11. Default directory is the current one.
d=$(fresh_repo j)
out=$(cd "$d" && AGENT_SANDBOX_ALLOW_VSCODE=1 sh "$script" 2>&1); rc=$?
check "defaults to cwd" test "$rc" -eq 0 -a -f "$d/.git/commondir"

# 12. Unfinished rebase / am / sequencer state: warned about, not refused.
for st in rebase-merge rebase-apply sequencer; do
  d=$(fresh_repo k-$st); mkdir "$d/.git/$st"
  AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
  check "$st present exits 0" test "$rc" -eq 0
  check "$st present warns and names it" grep -q "WARNING: $d/.git/$st exists" <<<"$out"
  check "$st warning says never continue" grep -q 'never continue it' <<<"$out"
  check "$st: sources still created" test -f "$d/.git/commondir" -a -d "$d/.vscode"
done
d=$(fresh_repo l); mkdir -p "$d/.git/worktrees/t1/rebase-merge"; printf '../..' > "$d/.git/worktrees/t1/commondir"
AGENT_SANDBOX_ALLOW_VSCODE=1 run "$d"; rc=$?
check "worktree rebase state exits 0" test "$rc" -eq 0
check "worktree rebase state named" grep -q 'worktrees/t1/rebase-merge exists' <<<"$out"

# 13. git was never executed, in any case above.
check "git never run" test ! -e "$tmp/GIT_WAS_RUN"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
