#!/usr/bin/env zsh
# Tests for scripts/agent-sandbox.zsh against a stub `docker` — no Docker needed.
#
#   zsh scripts/tests/agent_sandbox_test.zsh
#
# The stub logs every docker argv to a file and simulates state (image,
# container, running, firewall policy, labels, tmux present) with marker
# files in a temp dir. Each case resets the state, runs one agent command
# and compares the sequence of state-changing docker calls.

emulate -L zsh
setopt pipe_fail

here=${0:A:h}
src=$here/../agent-sandbox.zsh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export AGENT_SANDBOX_STUB_STATE=$tmp/state
mkdir -p "$AGENT_SANDBOX_STUB_STATE" "$tmp/bin" "$tmp/home"

cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
S="$AGENT_SANDBOX_STUB_STATE"
printf '%s\n' "$*" >> "$S/log"
sub="$1"; shift || true
case "$sub" in
  image)
    shift   # inspect
    if [ "${1:-}" = -f ]; then
      [ -e "$S/image" ] || exit 1
      case "$2" in
        *agent-sandbox.devcontainer-sha256*) cat "$S/image_hash" 2>/dev/null || echo '<no value>' ;;
        *agent-sandbox.user-uid*) cat "$S/image_uid" 2>/dev/null || echo '<no value>' ;;
      esac
    else
      [ -e "$S/image" ]
    fi ;;
  container)
    shift   # inspect
    if [ "${1:-}" = -f ]; then
      [ -e "$S/container" ] || exit 1
      case "$2" in
        *State.Running*) if [ -e "$S/running" ]; then echo true; else echo false; fi ;;
        *agent-sandbox.mode*) cat "$S/container_mode" 2>/dev/null || echo '<no value>' ;;
        *Mounts*) cat "$S/mount_src" 2>/dev/null || true ;;
      esac
    else
      [ -e "$S/container" ]
    fi ;;
  build)
    touch "$S/image"
    for a in "$@"; do case "$a" in agent-sandbox.devcontainer-sha256=*) echo "${a#*=}" > "$S/image_hash" ;; agent-sandbox.user-uid=*) echo "${a#*=}" > "$S/image_uid" ;; esac; done ;;
  run)
    [ -e "$S/image" ] || { echo "stub: no image" >&2; exit 125; }
    rm -f "$S/iptables_drop"
    touch "$S/container" "$S/running"
    echo normal > "$S/container_mode"
    : > "$S/module_mounts"
    for a in "$@"; do case "$a" in
      agent-sandbox.mode=*) echo "${a#*=}" > "$S/container_mode" ;;
      *dst=/workspace/.git/modules/*,readonly) d="${a#*dst=}"; d="${d%,readonly}"; echo "${d// /\\040}" >> "$S/module_mounts" ;;
    esac; done ;;
  start) rm -f "$S/iptables_drop"; touch "$S/running" ;;
  stop)  rm -f "$S/running" ;;
  rm)    rm -f "$S/container" "$S/running" "$S/container_mode" ;;
  port)  echo "3000/tcp -> 127.0.0.1:55000" ;;
  exec)
    [ -e "$S/running" ] || { echo "stub: container not running" >&2; exit 1; }
    case "$*" in
      *"iptables -S OUTPUT"*)
        if [ -e "$S/iptables_drop" ]; then echo "-P OUTPUT DROP"; echo "-A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT"; elif [ -e "$S/iptables_failclosed" ]; then echo "-P OUTPUT DROP"; else echo "-P OUTPUT ACCEPT"; fi ;;
      *init-firewall.sh*)
        if [ -e "$S/firewall_fail" ]; then echo "ERROR: stub firewall failure"; exit 1; fi
        touch "$S/iptables_drop"; echo "Firewall configuration complete" ;;
      *"command -v tmux"*) [ -e "$S/has_tmux" ] ;;
      *"pgrep -x claude"*) [ -e "$S/claude_running" ] ;;
      *"/proc/1/mountinfo"*)
        [ -e "$S/mountinfo_fail" ] && exit 1
        echo "60 1 0:40 / /workspace rw,relatime - virtiofs virtiofs0 rw"
        for p in .devcontainer .vscode .git/hooks .git/config .git/commondir; do
          [ "$p" = .git/config ] && [ -e "$S/mount_missing_config" ] && continue
          o=ro; [ "$p" = .git/hooks ] && [ -e "$S/mount_rw_hooks" ] && o=rw
          echo "61 60 0:40 /x /workspace/$p $o,nosuid,relatime - virtiofs virtiofs0 rw"
        done
        [ -e "$S/module_mounts" ] && while IFS= read -r d; do
          echo "62 60 0:40 /x $d ro,nosuid,relatime - virtiofs virtiofs0 rw"
        done < "$S/module_mounts"
        : ;;
      *) : ;;   # tmux / zsh attach: log only
    esac ;;
  *) echo "stub docker: unhandled: $sub $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$tmp/bin/docker"

export PATH=$tmp/bin:$PATH HOME=$tmp/home
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL
printf '[user]\n\tname = Test User\n\temail = test@example.com\n' > "$tmp/home/.gitconfig"

# A fake project: real git repo (gives .git/config + .git/hooks), a Dockerfile
# and a devcontainer.json with the flags line.
proj="$tmp/My Proj"
mkdir -p "$proj/.devcontainer"
( cd "$proj" && git init -q )
print 'FROM scratch' > "$proj/.devcontainer/Dockerfile"
write_devcontainer_json() {   # $1 = CLAUDE_SHORTCUT_FLAGS value
  cat > "$proj/.devcontainer/devcontainer.json" <<EOF
{
  "name": "Test",
  "build": {
    "args": {
      "CLAUDE_CODE_VERSION": "latest"
    }
  },
  "containerEnv": {
    // a comment
    "CLAUDE_SHORTCUT_FLAGS": "$1"
  }
}
EOF
}
write_devcontainer_json ""

source "$src"

pass=0 fail=0
ok()   { (( pass++ )); print -r -- "  ok   $1" }
bad()  { (( fail++ )); print -r -- "  FAIL $1"; [[ -n $2 ]] && print -r -- "       $2" }
assert_eq() {   # name expected actual
  if [[ $2 == $3 ]]; then ok "$1"; else bad "$1" "expected: $2"; print -r -- "       actual:   $3"; fi
}
assert_has() {  # name haystack needle
  if [[ $2 == *"$3"* ]]; then ok "$1"; else bad "$1" "missing: $3"; print -r -- "       in: $2"; fi
}
assert_not_has() {
  if [[ $2 != *"$3"* ]]; then ok "$1"; else bad "$1" "unexpected: $3"; fi
}

reset_state() {
  rm -rf "$AGENT_SANDBOX_STUB_STATE"; mkdir -p "$AGENT_SANDBOX_STUB_STATE"; : > "$AGENT_SANDBOX_STUB_STATE/log"
  for m in "$@"; do touch "$AGENT_SANDBOX_STUB_STATE/$m"; done
}
# State-changing docker calls, in order.
actions() {
  local line; local -a out
  while IFS= read -r line; do
    case $line in
      "build "*) out+=(build) ;;
      "run "*) out+=(run) ;;
      "start "*) out+=(start) ;;
      "stop "*) out+=(stop) ;;
      "rm "*) out+=(rm) ;;
      *init-firewall.sh*) out+=(firewall) ;;
      *" tmux new-session "*) out+=(tmux) ;;
      *"exec -it "*" zsh") out+=(zsh) ;;
    esac
  done < "$AGENT_SANDBOX_STUB_STATE/log"
  print -r -- "${(j: :)out}"
}
logline() { grep -m1 -- "^$1 " "$AGENT_SANDBOX_STUB_STATE/log" }
run_agent() {   # runs "$@" capturing rc, stderr
  err=$tmp/err; : > "$err"
  "$@" 2>"$err" >/dev/null
  rc=$?
  stderr=$(<"$err")
}

print "agent-sandbox.zsh lifecycle (stub docker)"

reset_state has_tmux
run_agent agent-sandbox "$proj"
assert_eq "nothing exists → build, run, firewall, tmux" "build run firewall tmux" "$(actions)"
assert_eq "  exit 0" 0 $rc
assert_has "  build labels the image with the .devcontainer hash" "$(logline build)" "agent-sandbox.devcontainer-sha256=$(_agent_sandbox_devcontainer_hash "$proj")"
assert_has "  build passes CLAUDE_CODE_VERSION from devcontainer.json" "$(logline build)" "CLAUDE_CODE_VERSION=latest"
assert_has "  build passes TZ" "$(logline build)" "TZ=$AGENT_SANDBOX_TZ"
if [[ $(uname -s) == Linux ]]; then
  assert_has "  build passes the host uid on Linux" "$(logline build)" "USER_UID=$(id -u) --build-arg USER_GID=$(id -g)"
  assert_has "  build labels the uid" "$(logline build)" "agent-sandbox.user-uid=$(id -u)"
else
  assert_has "  build keeps uid 1000 off Linux" "$(logline build)" "USER_UID=1000"
fi
assert_not_has "  no drift warning right after a build" "$stderr" "WARNING"
run_line=$(logline run)
assert_has "  run: workspace bind" "$run_line" "--mount type=bind,src=$proj,dst=/workspace "
assert_has "  run: .git is a mount point (not renameable)" "$run_line" "--mount type=bind,src=$proj/.git,dst=/workspace/.git "
assert_has "  run: .devcontainer read-only" "$run_line" "type=bind,src=$proj/.devcontainer,dst=/workspace/.devcontainer,readonly"
assert_has "  run: .git/hooks read-only" "$run_line" "type=bind,src=$proj/.git/hooks,dst=/workspace/.git/hooks,readonly"
assert_has "  run: .git/config read-only" "$run_line" "type=bind,src=$proj/.git/config,dst=/workspace/.git/config,readonly"
assert_has "  run: .git/commondir placeholder read-only" "$run_line" "type=bind,src=$proj/.git/commondir,dst=/workspace/.git/commondir,readonly"
assert_has "  run: .vscode read-only" "$run_line" "type=bind,src=$proj/.vscode,dst=/workspace/.vscode,readonly"
[[ -f $proj/.git/commondir && "$(<"$proj/.git/commondir")" == "." ]] && ok "  commondir placeholder created with '.'" || bad "  commondir placeholder created with '.'"
[[ $(wc -c < "$proj/.git/commondir") == 1 ]] && ok "  placeholder has no trailing newline" || bad "  placeholder has no trailing newline"
[[ -d $proj/.vscode ]] && ok "  .vscode created on the host when missing" || bad "  .vscode created on the host when missing"
assert_has "  run: config volume" "$run_line" "claude-my-proj-config:/home/node/.claude"
assert_has "  run: history volume" "$run_line" "claude-my-proj-history:/commandhistory"
assert_has "  run: mode label normal" "$run_line" "agent-sandbox.mode=normal"
assert_has "  run: AGENT_SANDBOX_CONTAINER_NAME" "$run_line" "AGENT_SANDBOX_CONTAINER_NAME=claude-my-proj"
assert_has "  run: git author from host" "$run_line" "GIT_AUTHOR_NAME=Test User"
assert_has "  run: git committer email from host" "$run_line" "GIT_COMMITTER_EMAIL=test@example.com"
assert_has "  run: telemetry off" "$run_line" "DISABLE_TELEMETRY=1"
assert_has "  run: error reporting off" "$run_line" "DISABLE_ERROR_REPORTING=1"
assert_has "  run: only NET_ADMIN/NET_RAW" "$run_line" "--cap-add NET_ADMIN --cap-add NET_RAW"
assert_not_has "  run: no --privileged" "$run_line" "--privileged"
assert_not_has "  run: no host network" "$run_line" "--network"
assert_not_has "  run: no docker socket" "$run_line" "docker.sock"
assert_not_has "  run: no ~/.ssh" "$run_line" ".ssh"

reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_eq "image only → run, firewall, tmux" "run firewall tmux" "$(actions)"

reset_state image container has_tmux
run_agent agent-sandbox "$proj"
assert_eq "stopped → start, firewall, tmux" "start firewall tmux" "$(actions)"

reset_state image container running iptables_drop has_tmux
run_agent agent-sandbox "$proj"
assert_eq "running with -P OUTPUT DROP → tmux only" "tmux" "$(actions)"

reset_state image container running has_tmux
run_agent agent-sandbox "$proj"
assert_eq "running without DROP policy → firewall, tmux" "firewall tmux" "$(actions)"

reset_state image container running iptables_failclosed has_tmux
run_agent agent-sandbox "$proj"
assert_eq "running with the fail-closed DROP table (no allowlist rule) → firewall re-applied" "firewall tmux" "$(actions)"

reset_state image firewall_fail has_tmux
run_agent agent-sandbox "$proj"
assert_eq "firewall fails → run, firewall, stop; no tmux" "run firewall stop" "$(actions)"
assert_eq "  non-zero exit" 1 $rc
assert_has "  says why" "$stderr" "firewall failed"
assert_has "  shows the script output" "$stderr" "stub firewall failure"

reset_state image container running iptables_drop
run_agent agent-sandbox "$proj"
assert_eq "no tmux in the image → zsh" "zsh" "$(actions)"
assert_has "  with a warning" "$stderr" "no tmux"

reset_state image container running iptables_drop has_tmux
run_agent agent-sandbox --no-tmux "$proj"
assert_eq "--no-tmux → zsh" "zsh" "$(actions)"
assert_not_has "  no warning" "$stderr" "no tmux"

reset_state image container running iptables_drop has_tmux
run_agent agent-sandbox-shell "$proj"
assert_eq "agent-sandbox-shell → zsh" "zsh" "$(actions)"

reset_state image container running iptables_drop has_tmux
run_agent agent-sandbox --bogus "$proj"
assert_eq "unknown option → exit 2" 2 $rc
assert_eq "  nothing run" "" "$(actions)"

print "read-only mounts verified inside the container"

reset_state image container running iptables_drop has_tmux
run_agent agent-sandbox "$proj"
assert_eq "all read-only mounts present → attaches" "tmux" "$(actions)"
assert_has "  reads the container's own mount table" "$(<$AGENT_SANDBOX_STUB_STATE/log)" "cat /proc/1/mountinfo"

reset_state image container running iptables_drop has_tmux mount_missing_config
run_agent agent-sandbox "$proj"
assert_eq ".git/config not mounted → refuses" 1 $rc
assert_eq "  no attach" "" "$(actions)"
assert_has "  names the path" "$stderr" "/workspace/.git/config (not mounted)"
assert_has "  points at agent-sandbox-recreate" "$stderr" "agent-sandbox-recreate $proj"
assert_has "  names the usual cause (host git rewrote .git/config)" "$stderr" "a git command on the HOST rewrote .git/config"

reset_state image container running iptables_drop has_tmux mount_rw_hooks
run_agent agent-sandbox "$proj"
assert_eq ".git/hooks mounted writable → refuses" 1 $rc
assert_has "  names the path" "$stderr" "/workspace/.git/hooks (mounted writable)"

reset_state image container running iptables_drop has_tmux mountinfo_fail
run_agent agent-sandbox "$proj"
assert_eq "mount table unreadable → refuses" 1 $rc
assert_has "  says why" "$stderr" "unverified"

mkdir -p "$proj/.git/modules/sub mod"; : > "$proj/.git/modules/sub mod/config"
reset_state image container running iptables_drop has_tmux
run_agent agent-sandbox "$proj"
assert_eq "submodule config not mounted → refuses" 1 $rc
assert_has "  names it" "$stderr" "/workspace/.git/modules/sub mod/config (not mounted)"
rm -rf "$proj/.git/modules"

print "setup mode"

reset_state image container running iptables_drop has_tmux
echo setup > "$AGENT_SANDBOX_STUB_STATE/container_mode"
run_agent agent-sandbox "$proj"
assert_eq "setup-mode container → plain agent-sandbox refuses" 1 $rc
assert_eq "  nothing run" "" "$(actions)"
assert_has "  points at agent-sandbox-rebuild" "$stderr" "agent-sandbox-rebuild"

reset_state image container running iptables_drop has_tmux
echo setup > "$AGENT_SANDBOX_STUB_STATE/container_mode"
run_agent agent-sandbox --setup "$proj"
assert_eq "agent-sandbox --setup re-attaches to a setup container" "tmux" "$(actions)"
assert_has "  loud warning" "$stderr" "SETUP MODE"

write_devcontainer_json "--dangerously-skip-permissions"
reset_state image has_tmux
run_agent agent-sandbox --setup "$proj"
assert_eq "agent-sandbox --setup, no container → run (setup), firewall, tmux" "run firewall tmux" "$(actions)"
run_line=$(logline run)
assert_has "  setup label" "$run_line" "agent-sandbox.mode=setup"
assert_not_has "  no read-only mounts" "$run_line" "readonly"
assert_not_has "  no .git mount either" "$run_line" "dst=/workspace/.git"
assert_has "  flags forced empty" "$run_line" "CLAUDE_SHORTCUT_FLAGS= "
assert_has "  firewall still applied" "$(actions)" "firewall"

reset_state image container has_tmux
run_agent agent-sandbox --setup "$proj"
assert_eq "agent-sandbox --setup on a stopped normal container → rm, run, firewall, tmux" "rm run firewall tmux" "$(actions)"

reset_state image container running has_tmux
run_agent agent-sandbox --setup "$proj"
assert_eq "agent-sandbox --setup on a running normal container → refuses" 1 $rc
assert_has "  says agent-sandbox-stop first" "$stderr" "agent-sandbox-stop"

reset_state image has_tmux
run_agent agent-sandbox-setup "$proj"
assert_has "agent-sandbox-setup = agent-sandbox --setup" "$(logline run)" "agent-sandbox.mode=setup"

print "flags, ports, drift, names, checks"

write_devcontainer_json "--dangerously-skip-permissions"
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_has "valid CLAUDE_SHORTCUT_FLAGS passed through" "$(logline run)" "CLAUDE_SHORTCUT_FLAGS=--dangerously-skip-permissions"
assert_not_has "  no warning" "$stderr" "ignoring CLAUDE_SHORTCUT_FLAGS"

write_devcontainer_json '--ok; rm -rf /'
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_has "invalid CLAUDE_SHORTCUT_FLAGS → empty" "$(logline run)" "CLAUDE_SHORTCUT_FLAGS= "
assert_has "  with a warning" "$stderr" "ignoring CLAUDE_SHORTCUT_FLAGS"
write_devcontainer_json ""

printf '# dev server\n3000\n  8080  # api\n\n' > "$proj/.devcontainer/agent-sandbox-ports"
reset_state image has_tmux
run_agent agent-sandbox "$proj"
run_line=$(logline run)
assert_has "agent-sandbox-ports: 3000 published loopback-only, ephemeral host port" "$run_line" "-p 127.0.0.1::3000"
assert_has "agent-sandbox-ports: 8080 too" "$run_line" "-p 127.0.0.1::8080"

printf '3000\n70000\n' > "$proj/.devcontainer/agent-sandbox-ports"
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_eq "agent-sandbox-ports: out-of-range line rejects the file" 1 $rc
assert_eq "  no container created" "" "$(actions)"
assert_has "  names the line" "$stderr" "agent-sandbox-ports:2"
printf '80a\n' > "$proj/.devcontainer/agent-sandbox-ports"
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_eq "agent-sandbox-ports: non-numeric line rejected" 1 $rc
rm -f "$proj/.devcontainer/agent-sandbox-ports"

reset_state image container running iptables_drop has_tmux
print -r -- "$(printf 'a%.0s' {1..64})" > "$AGENT_SANDBOX_STUB_STATE/image_hash"
run_agent agent-sandbox "$proj"
assert_has "drift: label mismatch → warning" "$stderr" ".devcontainer changed since the last build"
assert_has "  points at agent-sandbox-rebuild" "$stderr" "run agent-sandbox-rebuild"
assert_not_has "  does not tell the user to run git on the host" "$stderr" "git diff"
assert_eq "  still attaches" "tmux" "$(actions)"

reset_state image container running iptables_drop has_tmux
run_agent agent-sandbox "$proj"
assert_has "drift: image without label → warning" "$stderr" "carries no .devcontainer hash"

reset_state image container running iptables_drop has_tmux
_agent_sandbox_devcontainer_hash "$proj" > "$AGENT_SANDBOX_STUB_STATE/image_hash"
id -u > "$AGENT_SANDBOX_STUB_STATE/image_uid"
run_agent agent-sandbox "$proj"
assert_not_has "drift: matching label → no warning" "$stderr" "WARNING"
if [[ $(uname -s) == Linux && $(id -u) != 1000 ]]; then
  reset_state image container running iptables_drop has_tmux
  _agent_sandbox_devcontainer_hash "$proj" > "$AGENT_SANDBOX_STUB_STATE/image_hash"
  run_agent agent-sandbox "$proj"
  assert_has "uid: image without uid label on a non-1000 Linux host → warning" "$stderr" "built for uid"
fi
h1=$(_agent_sandbox_devcontainer_hash "$proj")
print '# touched' >> "$proj/.devcontainer/Dockerfile"
h2=$(_agent_sandbox_devcontainer_hash "$proj")
[[ $h1 != $h2 ]] && ok "hash changes when a file changes" || bad "hash changes when a file changes"
[[ $h1 =~ '^[0-9a-f]{64}$' ]] && ok "hash is 64 hex chars" || bad "hash is 64 hex chars" "$h1"

assert_eq "_agent_sandbox_name: 'My Proj' → claude-my-proj" "claude-my-proj" "$(_agent_sandbox_name "$proj")"
assert_eq "_agent_sandbox_name: trailing slash ignored" "claude-my-proj" "$(_agent_sandbox_name "$proj/")"
mkdir -p "$tmp/Web.App_v2"
assert_eq "_agent_sandbox_name: dots and underscores kept" "claude-web.app_v2" "$(_agent_sandbox_name "$tmp/Web.App_v2")"
mkdir -p "$tmp/a b@c"
assert_eq "_agent_sandbox_name: other chars → -" "claude-a-b-c" "$(_agent_sandbox_name "$tmp/a b@c")"
( cd "$proj" && assert_eq "_agent_sandbox_name: defaults to \$PWD" "claude-my-proj" "$(_agent_sandbox_name)" )

nogit="$tmp/nogit"; mkdir -p "$nogit/.devcontainer"; : > "$nogit/.devcontainer/Dockerfile"
_agent_sandbox_check "$nogit" 2>/dev/null && bad "_agent_sandbox_check: no .git → refused" || ok "_agent_sandbox_check: no .git → refused"
_agent_sandbox_check "$nogit" setup 2>/dev/null && ok "_agent_sandbox_check: setup mode needs only the Dockerfile" || bad "_agent_sandbox_check: setup mode needs only the Dockerfile"
_agent_sandbox_check "$tmp" 2>/dev/null && bad "_agent_sandbox_check: no Dockerfile → refused" || ok "_agent_sandbox_check: no Dockerfile → refused"
reset_state has_tmux
run_agent agent-sandbox "$nogit"
assert_eq "agent on a non-repo → nothing run" "" "$(actions)"

reset_state image container running iptables_drop has_tmux
print -r -- "$tmp/elsewhere/My Proj" > "$AGENT_SANDBOX_STUB_STATE/mount_src"
run_agent agent-sandbox "$proj"
assert_eq "same name, other folder mounted → refuses" 1 $rc
assert_eq "  nothing run" "" "$(actions)"
assert_has "  names the other folder" "$stderr" "$tmp/elsewhere/My Proj"
reset_state image container running iptables_drop has_tmux
print -r -- "$proj" > "$AGENT_SANDBOX_STUB_STATE/mount_src"
run_agent agent-sandbox "$proj"
assert_eq "same folder mounted → attaches" "tmux" "$(actions)"
comma="$tmp/a,b"; mkdir -p "$comma/.devcontainer"; : > "$comma/.devcontainer/Dockerfile"
_agent_sandbox_check "$comma" setup 2>/dev/null && bad "_agent_sandbox_check: comma in path → refused" || ok "_agent_sandbox_check: comma in path → refused"

print "rebuild / recreate / stop / ports"

( cd "$proj" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init )
state="$tmp/home/.cache/agent-sandbox/claude-my-proj"
built_hash() { _agent_sandbox_devcontainer_hash "$proj" > "$AGENT_SANDBOX_STUB_STATE/image_hash" }
reset_state has_tmux
run_agent agent-sandbox "$proj"
[[ -d $state/devcontainer ]] && ok "build snapshots .devcontainer outside the repo" || bad "build snapshots .devcontainer outside the repo" "$state"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox-rebuild "$proj"
assert_eq "agent-sandbox-rebuild, .devcontainer unchanged since build → build, rm, run (no prompt)" "build rm run" "$(actions)"
assert_has "  --pull --no-cache" "$(logline build)" "--pull --no-cache"

print 'x' >> "$proj/.devcontainer/Dockerfile"
reset_state image container running iptables_drop has_tmux
out=$(print n | agent-sandbox-rebuild "$proj" 2>&1); rc=$?
assert_eq "agent-sandbox-rebuild with changed .devcontainer and 'n' → aborted" 1 $rc
assert_eq "  nothing built" "" "$(actions)"
assert_has "  shows the diff against the last build" "$out" "+x"
assert_has "  names the file" "$out" "Dockerfile"
reset_state image container running iptables_drop has_tmux
out=$(print y | agent-sandbox-rebuild "$proj" 2>&1); rc=$?
assert_eq "agent-sandbox-rebuild with changes and 'y' → build, rm, run" "build rm run" "$(actions)"
( cd "$proj" && git -c user.name=t -c user.email=t@t commit -q -am "agent commit" )
reset_state image container running iptables_drop has_tmux
print -r -- "$(printf 'b%.0s' {1..64})" > "$AGENT_SANDBOX_STUB_STATE/image_hash"
out=$(print n | agent-sandbox-rebuild "$proj" 2>&1); rc=$?
assert_eq "agent-sandbox-rebuild: clean tree but hash differs from image → still asks; 'n' aborts" 1 $rc
reset_state image container running iptables_drop has_tmux
out=$(agent-sandbox-rebuild "$proj" </dev/null 2>&1); rc=$?
assert_eq "agent-sandbox-rebuild: no label on image, EOF on the prompt → aborted (default No)" 1 $rc

print "setup snapshot, commondir, nested repos (no git on the host)"

reset_state image has_tmux
run_agent agent-sandbox --setup "$proj"
[[ -f $state/setup-git-config && -d $state/setup-git-hooks ]] && ok "agent-sandbox --setup snapshots .git/config and .git/hooks first" || bad "agent-sandbox --setup snapshots .git/config and .git/hooks first"
cp "$proj/.git/config" "$tmp/config.orig"
print '[core]\n\tfsmonitor = "touch PLANTED; false"' >> "$proj/.git/config"
print '#!/bin/sh\ntouch PLANTED' > "$proj/.git/hooks/pre-commit"
reset_state image container running iptables_drop has_tmux; built_hash
out=$(print n | agent-sandbox-rebuild "$proj" 2>&1); rc=$?
assert_eq "agent-sandbox-rebuild after setup with a changed config → asks; 'n' aborts" 1 $rc
assert_has "  shows the config change" "$out" "fsmonitor"
assert_has "  shows the new hook" "$out" "pre-commit"
[[ -f $proj/PLANTED ]] && bad "  the gate ran no git on the host" || ok "  the gate ran no git on the host"
reset_state image container running iptables_drop has_tmux; built_hash
out=$(print y | agent-sandbox-rebuild "$proj" 2>&1); rc=$?
assert_eq "  'y' → build, rm, run and the snapshot is cleared" "build rm run" "$(actions)"
[[ -f $state/setup-git-config ]] && bad "  snapshot cleared after review" || ok "  snapshot cleared after review"
[[ -f $proj/PLANTED ]] && bad "  still no git run on the host" || ok "  still no git run on the host"
cp "$tmp/config.orig" "$proj/.git/config"; rm -f "$proj/.git/hooks/pre-commit"

print '../.alt' > "$proj/.git/commondir"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "commondir redirect present → agent-sandbox refuses to attach" 1 $rc
assert_has "  names the file" "$stderr" ".git/commondir"
assert_eq "  nothing run" "" "$(actions)"
run_agent agent-sandbox-rebuild "$proj"
assert_eq "  agent-sandbox-rebuild refuses too" 1 $rc
printf '.' > "$proj/.git/commondir"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "commondir placeholder '.' → attaches" "tmux" "$(actions)"
printf '.\n' > "$proj/.git/commondir"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "commondir '.' with a trailing newline → agent-sandbox refuses" 1 $rc
assert_eq "  nothing run" "" "$(actions)"
rm -f "$proj/.git/commondir"

mkdir -p "$proj/vendor/lib" && ( cd "$proj/vendor/lib" && git init -q )
mkdir -p "$proj/.claude/worktrees/wt/.git" "$proj/node_modules/pkg/.git"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "unlisted nested repo → agent-sandbox refuses" 1 $rc
assert_has "  names it" "$stderr" "vendor/lib"
assert_not_has "  harness worktrees are not reported" "$stderr" ".claude/worktrees"
assert_not_has "  node_modules is not reported" "$stderr" "node_modules"
assert_has "  points at agent-sandbox-nested-repos" "$stderr" "agent-sandbox-nested-repos"
assert_has "  hints at diff.ignoreSubmodules" "$stderr" "ignoreSubmodules"
assert_eq "  nothing run" "" "$(actions)"
run_agent agent-sandbox-rebuild "$proj"
assert_eq "  agent-sandbox-rebuild refuses too" 1 $rc
printf '# vendored\nvendor/lib/\n' > "$proj/.devcontainer/agent-sandbox-nested-repos"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "listed nested repo → attaches" "tmux" "$(actions)"
printf 'vendor/*\n' > "$proj/.devcontainer/agent-sandbox-nested-repos"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "glob pattern in the allowlist → attaches" "tmux" "$(actions)"
printf 'other/thing\n' > "$proj/.devcontainer/agent-sandbox-nested-repos"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "allowlist without it → refuses" 1 $rc
rm -f "$proj/.devcontainer/agent-sandbox-nested-repos"; rm -rf "$proj/vendor" "$proj/.claude" "$proj/node_modules"
( cd "$proj" && git checkout -q -- .devcontainer 2>/dev/null )

( cd "$proj" && git worktree add -q --no-track .claude/worktrees/wt -b wt HEAD )
[[ "$(<"$proj/.git/worktrees/wt/commondir")" == "../.." ]] && ok "linked worktree commondir is '../..' as git writes it" || bad "linked worktree commondir is '../..' as git writes it"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "linked worktree with normal commondir → attaches" "tmux" "$(actions)"
printf '../../../.alt' > "$proj/.git/worktrees/wt/commondir"
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox "$proj"
assert_eq "linked worktree commondir redirected → agent-sandbox refuses" 1 $rc
assert_has "  names the file" "$stderr" ".git/worktrees/wt/commondir"
printf '../..' > "$proj/.git/worktrees/wt/commondir"
( cd "$proj" && git worktree remove --force .claude/worktrees/wt && git branch -q -D wt )

# Unfinished rebase / am / sequencer state: warned about, never blocking,
# found with the shell (the directories are created by hand, no git runs).
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_not_has "no rebase state → no rebase warning" "$stderr" "unfinished rebase"
for st in rebase-merge rebase-apply sequencer; do
  mkdir "$proj/.git/$st"
  [[ $st == rebase-merge ]] && print 'exec touch PLANTED' > "$proj/.git/$st/git-rebase-todo"
  reset_state image has_tmux
  run_agent agent-sandbox "$proj"
  assert_eq ".git/$st present → agent-sandbox still attaches" "run firewall tmux" "$(actions)"
  assert_has "  warns and names .git/$st" "$stderr" "agent-sandbox:   .git/$st"
  assert_has "  says abort, never continue" "$stderr" "never continue it"
  rm -rf "$proj/.git/$st"
done
[[ -f $proj/PLANTED ]] && bad "  the planted exec line was not run" || ok "  the planted exec line was not run"
mkdir -p "$proj/.git/worktrees/wt/rebase-merge"
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_has "rebase state in a linked worktree → named" "$stderr" "agent-sandbox:   .git/worktrees/wt/rebase-merge"
rm -rf "$proj/.git/worktrees"
mkdir "$proj/.git/rebase-merge"
reset_state image container running iptables_drop has_tmux; built_hash
out=$(agent-sandbox-rebuild "$proj" 2>&1); rc=$?
assert_has "rebase state → the review gate warns too" "$out" "agent-sandbox:   .git/rebase-merge"
assert_eq "  and the rebuild still runs" "build rm run" "$(actions)"
rm -rf "$proj/.git/rebase-merge"

( cd "$proj" && git init -q "$tmp/subsrc" && cd "$tmp/subsrc" && echo a > a && git add a && git -c user.name=t -c user.email=t@t commit -q -m a )
( cd "$proj" && git -c protocol.file.allow=always submodule add -q "$tmp/subsrc" sub 2>/dev/null && git -c user.name=t -c user.email=t@t commit -q -m sub )
[[ -f $proj/.git/modules/sub/config ]] && ok "registered submodule has .git/modules/sub/config" || bad "registered submodule has .git/modules/sub/config"
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_eq "registered submodule, unlisted → refuses" 1 $rc
printf 'sub\n' > "$proj/.devcontainer/agent-sandbox-nested-repos"
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_eq "registered submodule, listed → run, firewall, tmux" "run firewall tmux" "$(actions)"
assert_has "  .git/modules/sub/config mounted read-only" "$(logline run)" "type=bind,src=$proj/.git/modules/sub/config,dst=/workspace/.git/modules/sub/config,readonly"
assert_has "  hints at diff.ignoreSubmodules while listed" "$stderr" "ignoreSubmodules"
( cd "$proj" && git config diff.ignoreSubmodules all )
reset_state image has_tmux
run_agent agent-sandbox "$proj"
assert_not_has "  no hint once the host config has it" "$stderr" "ignoreSubmodules"
( cd "$proj" && git config --unset diff.ignoreSubmodules; git rm -q -f sub 2>/dev/null; rm -rf .git/modules/sub sub; git -c user.name=t -c user.email=t@t commit -q -m rmsub 2>/dev/null; git checkout -q -- .devcontainer 2>/dev/null; rm -f .devcontainer/agent-sandbox-nested-repos )

n=$(grep -E '^[[:space:]]*[^#]*[[:space:]]git ' "$src" | grep -vE 'print|git config --global' | wc -l)
assert_eq "no git invocation in agent-sandbox.zsh except git config --global" 0 "$n"

reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-sandbox-recreate "$proj"
assert_eq "agent-sandbox-recreate → rm, run (no build)" "rm run" "$(actions)"
reset_state image container running iptables_drop has_tmux
out=$(print n | agent-sandbox-recreate "$proj" 2>&1); rc=$?
assert_eq "agent-sandbox-recreate with .devcontainer changed since build and 'n' → aborted" 1 $rc
assert_eq "  nothing recreated" "" "$(actions)"
reset_state
run_agent agent-sandbox-recreate "$proj"
assert_eq "agent-sandbox-recreate without image → error" 1 $rc

reset_state image container running iptables_drop has_tmux claude_running; built_hash
out=$(print n | agent-sandbox-recreate "$proj" 2>&1); rc=$?
assert_eq "agent-sandbox-recreate with Claude Code running and 'n' → aborted" 1 $rc
assert_eq "  container kept" "" "$(actions)"
assert_has "  says the session would end" "$out" "Claude Code is still running"
reset_state image container running iptables_drop has_tmux claude_running; built_hash
out=$(print y | agent-sandbox-recreate "$proj" 2>&1); rc=$?
assert_eq "agent-sandbox-recreate with Claude Code running and 'y' → rm, run" "rm run" "$(actions)"
reset_state image container running iptables_drop has_tmux claude_running; built_hash
out=$(agent-sandbox-rebuild "$proj" </dev/null 2>&1); rc=$?
assert_eq "agent-sandbox-rebuild with Claude Code running, EOF on the prompt → aborted before the build" 1 $rc
assert_eq "  nothing built or removed" "" "$(actions)"
reset_state image container iptables_drop has_tmux claude_running; built_hash
run_agent agent-sandbox-recreate "$proj"
assert_eq "agent-sandbox-recreate, container stopped → no session check, rm, run" "rm run" "$(actions)"

print "agent-sandbox-check (no docker, no git)"
reset_state
out=$(agent-sandbox-check "$proj" 2>&1); rc=$?
assert_eq "clean project → exit 0" 0 $rc
assert_has "  says what was checked" "$out" "no unlisted nested repository"
assert_eq "  no docker call" "" "$(<"$AGENT_SANDBOX_STUB_STATE/log")"
out=$(agent-sandbox-check -q "$proj" 2>&1); rc=$?
assert_eq "  -q on a clean project prints nothing" "0:" "$rc:$out"
mkdir -p "$proj/src/deep"
out=$(cd "$proj/src/deep" && agent-sandbox-check 2>&1); rc=$?
assert_has "started in a subfolder → checks the project root" "$out" "$proj: no commondir redirect"
out=$(agent-sandbox-check "$tmp/home" 2>&1); rc=$?
assert_eq "outside a project → exit 0" 0 $rc
assert_has "  says nothing was checked" "$out" "nothing checked"
out=$(agent-sandbox-check -q "$tmp/home" 2>&1)
assert_eq "  -q outside a project prints nothing" "" "$out"
run_agent agent-sandbox-check --bogus "$proj"
assert_eq "unknown option → exit 2" 2 $rc
mkdir -p "$proj/vendor/lib/.git" "$proj/vendor/lib/.devcontainer"
run_agent agent-sandbox-check "$proj"
assert_eq "unlisted nested repo → exit 1" 1 $rc
assert_has "  names it" "$stderr" "vendor/lib"
assert_has "  says not to run git on the host" "$stderr" "do not run git in $proj on the host"
out=$(cd "$proj/vendor/lib" && agent-sandbox-check -q 2>&1); rc=$?
assert_eq "started inside the nested repo (which has its own .git and .devcontainer) → still exit 1" 1 $rc
assert_has "  checked the outer project" "$out" "do not run git in $proj on the host"
printf 'vendor/lib\n' > "$proj/.devcontainer/agent-sandbox-nested-repos"
run_agent agent-sandbox-check "$proj"
assert_eq "listed nested repo → exit 0" 0 $rc
assert_has "  with the note about listed repositories" "$stderr" "nested repositories are listed"
run_agent agent-sandbox-check -q "$proj"
assert_eq "  -q leaves the note out" "0:" "$rc:$stderr"
rm -rf "$proj/vendor" "$proj/src" "$proj/.devcontainer/agent-sandbox-nested-repos"
cp "$proj/.git/commondir" "$tmp/commondir.orig"
print '../.alt' > "$proj/.git/commondir"
run_agent agent-sandbox-check -q "$proj"
assert_eq "commondir redirect → exit 1" 1 $rc
assert_has "  names the file" "$stderr" ".git/commondir"
cp "$tmp/commondir.orig" "$proj/.git/commondir"
mkdir "$proj/.git/rebase-merge"
run_agent agent-sandbox-check -q "$proj"
assert_eq "unfinished rebase → warning, exit 0" 0 $rc
assert_has "  names .git/rebase-merge" "$stderr" "agent-sandbox:   .git/rebase-merge"
rm -rf "$proj/.git/rebase-merge"
assert_eq "  no docker call in any case above" "" "$(<"$AGENT_SANDBOX_STUB_STATE/log")"

reset_state image container running
run_agent agent-sandbox-stop "$proj"
assert_eq "agent-sandbox-stop → stop" "stop" "$(actions)"

reset_state image container running
out=$(agent-sandbox-ports "$proj")
assert_has "agent-sandbox-ports → docker port <name>" "$(logline port)" "port claude-my-proj"
assert_has "  prints the mapping" "$out" "127.0.0.1:55000"

print "sourcing"
out=$(zsh -fc "
  local v; typeset -A before; for v in \${(k)parameters}; do before[\$v]=1; done
  source '$src'
  for v in \${(k)parameters}; do [[ -n \${before[\$v]} ]] || print -r -- \$v; done
")
assert_eq "sourcing defines only AGENT_SANDBOX_TZ" "AGENT_SANDBOX_TZ" "$out"
out=$(zsh -fc "source '$src'; print -r -- \${(k)functions}" | tr ' ' '\n' | grep -c '^_\?agent')
(( out >= 15 )) && ok "functions defined ($out)" || bad "functions defined" "$out"
zsh -n "$src" && ok "zsh -n passes" || bad "zsh -n passes"
v=$(grep -m1 -E '^# AGENT_SANDBOX_VERSION=' "$src")
[[ -n $v ]] && ok "header has AGENT_SANDBOX_VERSION ($v)" || bad "header has AGENT_SANDBOX_VERSION"
grep -q 'OUTSIDE any folder an agent can write' "$src" && ok "header warns about placement" || bad "header warns about placement"
grep -q 'never symlink' "$src" && ok "header forbids symlinking" || bad "header forbids symlinking"
n=$(grep -cE '^_?agent[a-z-]*\(\)' "$src")
m=$(awk '/^_?agent[a-z-]*\(\)/ { def=1; if ($0 ~ /emulate -L zsh/) { c++; def=0 }; next } def { if ($0 ~ /^[ \t]*emulate -L zsh/) c++; def=0 } END { print c+0 }' "$src")
assert_eq "every function starts with emulate -L zsh ($n functions)" "$n" "$m"

print
print "passed: $pass  failed: $fail"
(( fail == 0 ))
