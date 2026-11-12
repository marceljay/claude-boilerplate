#!/usr/bin/env zsh
# Tests for scripts/agent.zsh against a stub `docker` — no Docker needed.
#
#   zsh scripts/tests/agent_zsh_test.zsh
#
# The stub logs every docker argv to a file and simulates state (image,
# container, running, firewall policy, labels, tmux present) with marker
# files in a temp dir. Each case resets the state, runs one agent command
# and compares the sequence of state-changing docker calls.

emulate -L zsh
setopt pipe_fail

here=${0:A:h}
src=$here/../agent.zsh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export AGENT_STUB_STATE=$tmp/state
mkdir -p "$AGENT_STUB_STATE" "$tmp/bin" "$tmp/home"

cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
S="$AGENT_STUB_STATE"
printf '%s\n' "$*" >> "$S/log"
sub="$1"; shift || true
case "$sub" in
  image)
    shift   # inspect
    if [ "${1:-}" = -f ]; then
      [ -e "$S/image" ] || exit 1
      case "$2" in
        *agent.devcontainer-sha256*) cat "$S/image_hash" 2>/dev/null || echo '<no value>' ;;
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
        *agent.mode*) cat "$S/container_mode" 2>/dev/null || echo '<no value>' ;;
        *Mounts*) cat "$S/mount_src" 2>/dev/null || true ;;
      esac
    else
      [ -e "$S/container" ]
    fi ;;
  build)
    touch "$S/image"
    for a in "$@"; do case "$a" in agent.devcontainer-sha256=*) echo "${a#*=}" > "$S/image_hash" ;; esac; done ;;
  run)
    [ -e "$S/image" ] || { echo "stub: no image" >&2; exit 125; }
    rm -f "$S/iptables_drop"
    touch "$S/container" "$S/running"
    echo normal > "$S/container_mode"
    for a in "$@"; do case "$a" in agent.mode=*) echo "${a#*=}" > "$S/container_mode" ;; esac; done ;;
  start) rm -f "$S/iptables_drop"; touch "$S/running" ;;
  stop)  rm -f "$S/running" ;;
  rm)    rm -f "$S/container" "$S/running" "$S/container_mode" ;;
  port)  echo "3000/tcp -> 127.0.0.1:55000" ;;
  exec)
    [ -e "$S/running" ] || { echo "stub: container not running" >&2; exit 1; }
    case "$*" in
      *"iptables -S OUTPUT"*)
        if [ -e "$S/iptables_drop" ]; then echo "-P OUTPUT DROP"; else echo "-P OUTPUT ACCEPT"; fi ;;
      *init-firewall.sh*)
        if [ -e "$S/firewall_fail" ]; then echo "ERROR: stub firewall failure"; exit 1; fi
        touch "$S/iptables_drop"; echo "Firewall configuration complete" ;;
      *"command -v tmux"*) [ -e "$S/has_tmux" ] ;;
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
  rm -rf "$AGENT_STUB_STATE"; mkdir -p "$AGENT_STUB_STATE"; : > "$AGENT_STUB_STATE/log"
  for m in "$@"; do touch "$AGENT_STUB_STATE/$m"; done
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
  done < "$AGENT_STUB_STATE/log"
  print -r -- "${(j: :)out}"
}
logline() { grep -m1 -- "^$1 " "$AGENT_STUB_STATE/log" }
run_agent() {   # runs "$@" capturing rc, stderr
  err=$tmp/err; : > "$err"
  "$@" 2>"$err" >/dev/null
  rc=$?
  stderr=$(<"$err")
}

print "agent.zsh lifecycle (stub docker)"

reset_state has_tmux
run_agent agent "$proj"
assert_eq "nothing exists → build, run, firewall, tmux" "build run firewall tmux" "$(actions)"
assert_eq "  exit 0" 0 $rc
assert_has "  build labels the image with the .devcontainer hash" "$(logline build)" "agent.devcontainer-sha256=$(_agent_devcontainer_hash "$proj")"
assert_has "  build passes CLAUDE_CODE_VERSION from devcontainer.json" "$(logline build)" "CLAUDE_CODE_VERSION=latest"
assert_has "  build passes TZ" "$(logline build)" "TZ=$AGENT_TZ"
assert_not_has "  no drift warning right after a build" "$stderr" "WARNING"
run_line=$(logline run)
assert_has "  run: workspace bind" "$run_line" "--mount type=bind,src=$proj,dst=/workspace "
assert_has "  run: .git is a mount point (not renameable)" "$run_line" "--mount type=bind,src=$proj/.git,dst=/workspace/.git "
assert_has "  run: .devcontainer read-only" "$run_line" "type=bind,src=$proj/.devcontainer,dst=/workspace/.devcontainer,readonly"
assert_has "  run: .git/hooks read-only" "$run_line" "type=bind,src=$proj/.git/hooks,dst=/workspace/.git/hooks,readonly"
assert_has "  run: .git/config read-only" "$run_line" "type=bind,src=$proj/.git/config,dst=/workspace/.git/config,readonly"
assert_has "  run: config volume" "$run_line" "claude-my-proj-config:/home/node/.claude"
assert_has "  run: history volume" "$run_line" "claude-my-proj-history:/commandhistory"
assert_has "  run: mode label normal" "$run_line" "agent.mode=normal"
assert_has "  run: AGENT_CONTAINER_NAME" "$run_line" "AGENT_CONTAINER_NAME=claude-my-proj"
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
run_agent agent "$proj"
assert_eq "image only → run, firewall, tmux" "run firewall tmux" "$(actions)"

reset_state image container has_tmux
run_agent agent "$proj"
assert_eq "stopped → start, firewall, tmux" "start firewall tmux" "$(actions)"

reset_state image container running iptables_drop has_tmux
run_agent agent "$proj"
assert_eq "running with -P OUTPUT DROP → tmux only" "tmux" "$(actions)"

reset_state image container running has_tmux
run_agent agent "$proj"
assert_eq "running without DROP policy → firewall, tmux" "firewall tmux" "$(actions)"

reset_state image firewall_fail has_tmux
run_agent agent "$proj"
assert_eq "firewall fails → run, firewall, stop; no tmux" "run firewall stop" "$(actions)"
assert_eq "  non-zero exit" 1 $rc
assert_has "  says why" "$stderr" "firewall failed"
assert_has "  shows the script output" "$stderr" "stub firewall failure"

reset_state image container running iptables_drop
run_agent agent "$proj"
assert_eq "no tmux in the image → zsh" "zsh" "$(actions)"
assert_has "  with a warning" "$stderr" "no tmux"

reset_state image container running iptables_drop has_tmux
run_agent agent --no-tmux "$proj"
assert_eq "--no-tmux → zsh" "zsh" "$(actions)"
assert_not_has "  no warning" "$stderr" "no tmux"

reset_state image container running iptables_drop has_tmux
run_agent agent-shell "$proj"
assert_eq "agent-shell → zsh" "zsh" "$(actions)"

reset_state image container running iptables_drop has_tmux
run_agent agent --bogus "$proj"
assert_eq "unknown option → exit 2" 2 $rc
assert_eq "  nothing run" "" "$(actions)"

print "setup mode"

reset_state image container running iptables_drop has_tmux
echo setup > "$AGENT_STUB_STATE/container_mode"
run_agent agent "$proj"
assert_eq "setup-mode container → plain agent refuses" 1 $rc
assert_eq "  nothing run" "" "$(actions)"
assert_has "  points at agent-rebuild" "$stderr" "agent-rebuild"

reset_state image container running iptables_drop has_tmux
echo setup > "$AGENT_STUB_STATE/container_mode"
run_agent agent --setup "$proj"
assert_eq "agent --setup re-attaches to a setup container" "tmux" "$(actions)"
assert_has "  loud warning" "$stderr" "SETUP MODE"

write_devcontainer_json "--dangerously-skip-permissions"
reset_state image has_tmux
run_agent agent --setup "$proj"
assert_eq "agent --setup, no container → run (setup), firewall, tmux" "run firewall tmux" "$(actions)"
run_line=$(logline run)
assert_has "  setup label" "$run_line" "agent.mode=setup"
assert_not_has "  no read-only overlays" "$run_line" "readonly"
assert_not_has "  no .git mount either" "$run_line" "dst=/workspace/.git"
assert_has "  flags forced empty" "$run_line" "CLAUDE_SHORTCUT_FLAGS= "
assert_has "  firewall still applied" "$(actions)" "firewall"

reset_state image container has_tmux
run_agent agent --setup "$proj"
assert_eq "agent --setup on a stopped normal container → rm, run, firewall, tmux" "rm run firewall tmux" "$(actions)"

reset_state image container running has_tmux
run_agent agent --setup "$proj"
assert_eq "agent --setup on a running normal container → refuses" 1 $rc
assert_has "  says agent-stop first" "$stderr" "agent-stop"

reset_state image has_tmux
run_agent agent-setup "$proj"
assert_has "agent-setup = agent --setup" "$(logline run)" "agent.mode=setup"

print "flags, ports, drift, names, checks"

write_devcontainer_json "--dangerously-skip-permissions"
reset_state image has_tmux
run_agent agent "$proj"
assert_has "valid CLAUDE_SHORTCUT_FLAGS passed through" "$(logline run)" "CLAUDE_SHORTCUT_FLAGS=--dangerously-skip-permissions"
assert_not_has "  no warning" "$stderr" "ignoring CLAUDE_SHORTCUT_FLAGS"

write_devcontainer_json '--ok; rm -rf /'
reset_state image has_tmux
run_agent agent "$proj"
assert_has "invalid CLAUDE_SHORTCUT_FLAGS → empty" "$(logline run)" "CLAUDE_SHORTCUT_FLAGS= "
assert_has "  with a warning" "$stderr" "ignoring CLAUDE_SHORTCUT_FLAGS"
write_devcontainer_json ""

printf '# dev server\n3000\n  8080  # api\n\n' > "$proj/.devcontainer/agent-ports"
reset_state image has_tmux
run_agent agent "$proj"
run_line=$(logline run)
assert_has "agent-ports: 3000 published loopback-only, ephemeral host port" "$run_line" "-p 127.0.0.1::3000"
assert_has "agent-ports: 8080 too" "$run_line" "-p 127.0.0.1::8080"

printf '3000\n70000\n' > "$proj/.devcontainer/agent-ports"
reset_state image has_tmux
run_agent agent "$proj"
assert_eq "agent-ports: out-of-range line rejects the file" 1 $rc
assert_eq "  no container created" "" "$(actions)"
assert_has "  names the line" "$stderr" "agent-ports:2"
printf '80a\n' > "$proj/.devcontainer/agent-ports"
reset_state image has_tmux
run_agent agent "$proj"
assert_eq "agent-ports: non-numeric line rejected" 1 $rc
rm -f "$proj/.devcontainer/agent-ports"

reset_state image container running iptables_drop has_tmux
print -r -- "$(printf 'a%.0s' {1..64})" > "$AGENT_STUB_STATE/image_hash"
run_agent agent "$proj"
assert_has "drift: label mismatch → warning" "$stderr" ".devcontainer changed since the last build"
assert_eq "  still attaches" "tmux" "$(actions)"

reset_state image container running iptables_drop has_tmux
run_agent agent "$proj"
assert_has "drift: image without label → warning" "$stderr" "carries no .devcontainer hash"

reset_state image container running iptables_drop has_tmux
_agent_devcontainer_hash "$proj" > "$AGENT_STUB_STATE/image_hash"
run_agent agent "$proj"
assert_not_has "drift: matching label → no warning" "$stderr" "WARNING"
h1=$(_agent_devcontainer_hash "$proj")
print '# touched' >> "$proj/.devcontainer/Dockerfile"
h2=$(_agent_devcontainer_hash "$proj")
[[ $h1 != $h2 ]] && ok "hash changes when a file changes" || bad "hash changes when a file changes"
[[ $h1 =~ '^[0-9a-f]{64}$' ]] && ok "hash is 64 hex chars" || bad "hash is 64 hex chars" "$h1"

assert_eq "_agent_name: 'My Proj' → claude-my-proj" "claude-my-proj" "$(_agent_name "$proj")"
assert_eq "_agent_name: trailing slash ignored" "claude-my-proj" "$(_agent_name "$proj/")"
mkdir -p "$tmp/Web.App_v2"
assert_eq "_agent_name: dots and underscores kept" "claude-web.app_v2" "$(_agent_name "$tmp/Web.App_v2")"
mkdir -p "$tmp/a b@c"
assert_eq "_agent_name: other chars → -" "claude-a-b-c" "$(_agent_name "$tmp/a b@c")"
( cd "$proj" && assert_eq "_agent_name: defaults to \$PWD" "claude-my-proj" "$(_agent_name)" )

nogit="$tmp/nogit"; mkdir -p "$nogit/.devcontainer"; : > "$nogit/.devcontainer/Dockerfile"
_agent_check "$nogit" 2>/dev/null && bad "_agent_check: no .git → refused" || ok "_agent_check: no .git → refused"
_agent_check "$nogit" setup 2>/dev/null && ok "_agent_check: setup mode needs only the Dockerfile" || bad "_agent_check: setup mode needs only the Dockerfile"
_agent_check "$tmp" 2>/dev/null && bad "_agent_check: no Dockerfile → refused" || ok "_agent_check: no Dockerfile → refused"
reset_state has_tmux
run_agent agent "$nogit"
assert_eq "agent on a non-repo → nothing run" "" "$(actions)"

reset_state image container running iptables_drop has_tmux
print -r -- "$tmp/elsewhere/My Proj" > "$AGENT_STUB_STATE/mount_src"
run_agent agent "$proj"
assert_eq "same name, other folder mounted → refuses" 1 $rc
assert_eq "  nothing run" "" "$(actions)"
assert_has "  names the other folder" "$stderr" "$tmp/elsewhere/My Proj"
reset_state image container running iptables_drop has_tmux
print -r -- "$proj" > "$AGENT_STUB_STATE/mount_src"
run_agent agent "$proj"
assert_eq "same folder mounted → attaches" "tmux" "$(actions)"
comma="$tmp/a,b"; mkdir -p "$comma/.devcontainer"; : > "$comma/.devcontainer/Dockerfile"
_agent_check "$comma" setup 2>/dev/null && bad "_agent_check: comma in path → refused" || ok "_agent_check: comma in path → refused"

print "rebuild / recreate / stop / ports"

( cd "$proj" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init )
built_hash() { _agent_devcontainer_hash "$proj" > "$AGENT_STUB_STATE/image_hash" }
reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-rebuild "$proj"
assert_eq "agent-rebuild, .devcontainer unchanged since build → build, rm, run (no prompt)" "build rm run" "$(actions)"
assert_has "  --pull --no-cache" "$(logline build)" "--pull --no-cache"
reset_state image container running iptables_drop has_tmux; built_hash
out=$(agent-rebuild "$proj" 2>/dev/null)
assert_has "  reminder names git diff -- .devcontainer" "$out" "git diff -- .devcontainer"

print 'x' >> "$proj/.devcontainer/Dockerfile"
reset_state image container running iptables_drop has_tmux
out=$(print n | agent-rebuild "$proj" 2>&1); rc=$?
assert_eq "agent-rebuild with uncommitted .devcontainer changes and 'n' → aborted" 1 $rc
assert_eq "  nothing built" "" "$(actions)"
assert_has "  lists the change" "$out" "Dockerfile"
reset_state image container running iptables_drop has_tmux
out=$(print y | agent-rebuild "$proj" 2>&1); rc=$?
assert_eq "agent-rebuild with changes and 'y' → build, rm, run" "build rm run" "$(actions)"
( cd "$proj" && git -c user.name=t -c user.email=t@t commit -q -am "agent commit" )
reset_state image container running iptables_drop has_tmux
print -r -- "$(printf 'b%.0s' {1..64})" > "$AGENT_STUB_STATE/image_hash"
out=$(print n | agent-rebuild "$proj" 2>&1); rc=$?
assert_eq "agent-rebuild: clean tree but hash differs from image → still asks; 'n' aborts" 1 $rc
assert_has "  says the changes are committed" "$out" "committed"
reset_state image container running iptables_drop has_tmux
out=$(agent-rebuild "$proj" </dev/null 2>&1); rc=$?
assert_eq "agent-rebuild: no label on image, EOF on the prompt → aborted (default No)" 1 $rc

reset_state image container running iptables_drop has_tmux; built_hash
run_agent agent-recreate "$proj"
assert_eq "agent-recreate → rm, run (no build)" "rm run" "$(actions)"
reset_state image container running iptables_drop has_tmux
out=$(print n | agent-recreate "$proj" 2>&1); rc=$?
assert_eq "agent-recreate with .devcontainer changed since build and 'n' → aborted" 1 $rc
assert_eq "  nothing recreated" "" "$(actions)"
reset_state
run_agent agent-recreate "$proj"
assert_eq "agent-recreate without image → error" 1 $rc

reset_state image container running
run_agent agent-stop "$proj"
assert_eq "agent-stop → stop" "stop" "$(actions)"

reset_state image container running
out=$(agent-ports "$proj")
assert_has "agent-ports → docker port <name>" "$(logline port)" "port claude-my-proj"
assert_has "  prints the mapping" "$out" "127.0.0.1:55000"

print "sourcing"
out=$(zsh -fc "
  local v; typeset -A before; for v in \${(k)parameters}; do before[\$v]=1; done
  source '$src'
  for v in \${(k)parameters}; do [[ -n \${before[\$v]} ]] || print -r -- \$v; done
")
assert_eq "sourcing defines only AGENT_TZ" "AGENT_TZ" "$out"
out=$(zsh -fc "source '$src'; print -r -- \${(k)functions}" | tr ' ' '\n' | grep -c '^_\?agent')
(( out >= 15 )) && ok "functions defined ($out)" || bad "functions defined" "$out"
zsh -n "$src" && ok "zsh -n passes" || bad "zsh -n passes"
v=$(grep -m1 -E '^# AGENT_ZSH_VERSION=' "$src")
[[ -n $v ]] && ok "header has AGENT_ZSH_VERSION ($v)" || bad "header has AGENT_ZSH_VERSION"
grep -q 'OUTSIDE any folder an agent can write' "$src" && ok "header warns about placement" || bad "header warns about placement"
grep -q 'never symlink' "$src" && ok "header forbids symlinking" || bad "header forbids symlinking"
n=$(grep -cE '^_?agent[a-z-]*\(\)' "$src")
m=$(awk '/^_?agent[a-z-]*\(\)/ { def=1; if ($0 ~ /emulate -L zsh/) { c++; def=0 }; next } def { if ($0 ~ /^[ \t]*emulate -L zsh/) c++; def=0 } END { print c+0 }' "$src")
assert_eq "every function starts with emulate -L zsh ($n functions)" "$n" "$m"

print
print "passed: $pass  failed: $fail"
(( fail == 0 ))
