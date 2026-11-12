# agent.zsh: run Claude Code in a per-project Docker container — plain Docker
# from the host, no devcontainer CLI, no VS Code attach.
#
# AGENT_ZSH_VERSION=1.2.0
#
# Source this from ~/.zshrc (`scripts/sync-harness.sh --install-shell` copies
# it to ~/.config/zsh/agent.zsh and prints the line). Keep the installed copy
# OUTSIDE any folder an agent can write to — a project, the boilerplate
# checkout, a dotfiles repo you run Claude in — and never symlink it into a
# repo: this file decides what the container can see, so whoever can edit it
# controls the next `agent` you type. Update it only through the install step,
# which shows the diff first.
#
#   agent [--no-tmux] [dir]  build/create/start whatever is missing, make sure
#                            the firewall is active, attach to tmux inside
#                            (plain zsh if the image has no tmux, or with
#                            --no-tmux)
#   agent --setup [dir]      one-time SETUP container: no read-only overlays,
#   agent-setup [dir]        permission prompts forced on. For /init and the
#                            detach script. Plain `agent` refuses to attach to
#                            it afterwards — review, then agent-rebuild.
#   agent-rebuild [dir]      fresh base image + newest Claude Code, new
#                            container (review `git diff -- .devcontainer` first)
#   agent-recreate [dir]     new container from the existing image (after env,
#                            port, overlay or .git/config changes), no build
#   agent-stop [dir]         stop the container (sign-in and history are kept)
#   agent-ports [dir]        host ports published for the container
#   agent-shell [dir]        plain zsh, no tmux (same as agent --no-tmux)
#
# Names: image, container and volumes are claude-<folder name>, lowercased,
# anything outside [a-z0-9_.-] replaced by "-". A container or image created
# by hand under that name is picked up as it is. Two projects with the same
# folder name share the name: `agent` refuses to attach when the existing
# container's /workspace is another folder (rename one of them).
#
# What the container gets, and nothing else:
#   - the project folder at /workspace, read-write — with .devcontainer,
#     .git/hooks and .git/config mounted read-only on top (normal mode), so
#     an agent cannot change what the next rebuild runs, what git runs on the
#     host, or where git pushes. .git itself is also a (read-write) mount so
#     it cannot be renamed away and replaced by a writable copy — a parent
#     directory of a mount point can be renamed, a mount point cannot.
#     Caveat: git rewrites .git/config by renaming a new file over it, so
#     after a host-side `git remote add`, `git config` or `push -u` the
#     container still sees the OLD inode — `agent-recreate`.
#   - two named volumes: <name>-config (/home/node/.claude: sign-in, memory,
#     sessions) and <name>-history (/commandhistory)
#   - the environment devcontainer.json's containerEnv sets (keep the two in
#     step), the author identity from the host's global git config (env vars
#     — they win over a per-repo user.name/email), the Claude Code telemetry
#     opt-outs, and AGENT_CONTAINER_NAME so commands inside can print exact
#     `docker port` hints
#   - NET_ADMIN/NET_RAW for the firewall; never --privileged, --network host,
#     the Docker socket, ~/.ssh, SSH_AUTH_SOCK or any other host path
#   - ports listed in .devcontainer/agent-ports, published on 127.0.0.1 with
#     an ephemeral host port (`agent-ports` shows the mapping)
#
# Labels: the image carries a sha256 of the .devcontainer directory at build
# time (agent.devcontainer-sha256 — `agent` warns when it no longer matches),
# the container records which mode created it (agent.mode=normal|setup).
#
# Requires zsh 5.9 or newer (macOS ships it; on Linux install zsh — bash
# users get a shim from `sync-harness.sh --install-shell`) and `docker` on
# PATH. Sourcing defines functions and the one variable below; nothing else.
#
# Linux hosts: native Docker Engine shows the repo with the host user's uid,
# so the image is built with USER_UID/USER_GID = your ids (Docker Desktop
# maps ownership itself and keeps the defaults). The image is labelled with
# the uid it was built for; `agent` warns when it no longer matches.

typeset -g AGENT_TZ=${AGENT_TZ:-${TZ:-Europe/Berlin}}   # container time zone

_agent_dir() { emulate -L zsh; print -r -- ${${1:-$PWD}:A} }

_agent_name() {
  emulate -L zsh
  local dir=$(_agent_dir "$1")
  local n=${(L)dir:t}
  print -r -- "claude-${n//[^a-z0-9_.-]/-}"
}

# Refuse folders that would make docker create missing bind sources on the
# host (a bind of a nonexistent path appears as a new root-owned directory).
# $2 = setup: only the Dockerfile is required. Setup mode mounts nothing
# below the project folder, and the detach flow (scripts/new-project.sh)
# deletes and re-inits .git — which the overlays make impossible anyway.
_agent_check() {
  emulate -L zsh
  local dir=$(_agent_dir "$1")
  if [[ $dir == *,* ]]; then
    print -u2 "agent: $dir contains a comma, which docker's --mount syntax cannot carry; rename the folder"
    return 1
  fi
  if [[ ! -f $dir/.devcontainer/Dockerfile ]]; then
    print -u2 "agent: $dir has no .devcontainer/Dockerfile"
    return 1
  fi
  [[ $2 == setup ]] && return 0
  [[ -f $dir/.git/config && -d $dir/.git/hooks ]] && return 0
  print -u2 "agent: $dir needs .git/config and .git/hooks (a git repository) for the read-only overlays"
  return 1
}

# sha256 over the sorted file list + contents of .devcontainer. macOS ships
# shasum, Linux sha256sum; both print "<hash>  -" for stdin.
_agent_devcontainer_hash() {
  emulate -L zsh
  local dir=$(_agent_dir "$1") f
  local -a sum
  if (( $+commands[shasum] )); then sum=(shasum -a 256)
  elif (( $+commands[sha256sum] )); then sum=(sha256sum)
  else print -u2 "agent: need shasum or sha256sum on PATH"; return 1
  fi
  setopt localoptions pipefail   # a failed cd must not yield the hash of nothing
  (
    cd "$dir/.devcontainer" || exit 1
    for f in **/*(.DN); do          # sorted by name; regular files only
      [[ ${f:t} == .DS_Store ]] && continue
      print -r -- "$f"
      cat -- "$f"
    done
  ) | "${sum[@]}" | cut -d' ' -f1
}

# First `"key": "value"` line of a JSONC file → value (empty when absent).
# Same line-based reading sync-harness.sh uses; comments are left alone.
_agent_json_line_value() {
  emulate -L zsh
  { grep -m1 -E "^[[:space:]]*\"$2\":" "$1" 2>/dev/null || true } \
    | sed -E 's/^[^:]*:[[:space:]]*"([^"]*)".*$/\1/'
}

# CLAUDE_SHORTCUT_FLAGS from devcontainer.json. Only empty or space-separated
# --long-flags pass; anything else (a quote, a path, `;`) is a warning and
# the shortcuts run with prompts on.
_agent_shortcut_flags() {
  emulate -L zsh
  local dir=$(_agent_dir "$1") flags
  flags=$(_agent_json_line_value "$dir/.devcontainer/devcontainer.json" CLAUDE_SHORTCUT_FLAGS)
  if [[ $flags =~ '^(--[a-z0-9-]+( |$))*$' ]]; then
    print -r -- "$flags"
    return 0
  fi
  print -u2 "agent: ignoring CLAUDE_SHORTCUT_FLAGS in devcontainer.json ('$flags'): only space-separated --long-flags are accepted; the shortcuts will prompt"
  print -r -- ""
}

# CLAUDE_CODE_VERSION build arg from devcontainer.json (devcontainer.json
# overrides the Dockerfile default there, so do the same here).
_agent_build_version_args() {
  emulate -L zsh
  local dir=$(_agent_dir "$1") v
  v=$(_agent_json_line_value "$dir/.devcontainer/devcontainer.json" CLAUDE_CODE_VERSION)
  if [[ -n $v && $v =~ '^[A-Za-z0-9._-]+$' ]]; then
    print -r -- "--build-arg"
    print -r -- "CLAUDE_CODE_VERSION=$v"
  fi
}

# .devcontainer/agent-ports → `-p 127.0.0.1::<port>` pairs, one token per
# line. One bad line rejects the whole file (and the create). The file sits
# under the read-only overlay, so only the host side can change it.
_agent_port_args() {
  emulate -L zsh
  local dir=$(_agent_dir "$1") f line n=0
  f=$dir/.devcontainer/agent-ports
  [[ -f $f ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    (( n++ ))
    line=${line%%#*}
    line=${line//[[:space:]]/}
    [[ -z $line ]] && continue
    if [[ $line != <1-65535> ]]; then
      print -u2 "agent: $f:$n: not a port (1-65535): '$line' — fix the file; no ports published"
      return 1
    fi
    print -r -- "-p"
    print -r -- "127.0.0.1::$line"
  done < "$f"
}

# Host ids the container user should have: the real ones on Linux (native
# Docker Engine keeps host ownership on bind mounts), the Dockerfile default
# everywhere else (Docker Desktop maps ownership itself).
_agent_host_uid() { emulate -L zsh; [[ $(uname -s) == Linux ]] && id -u || print 1000 }
_agent_host_gid() { emulate -L zsh; [[ $(uname -s) == Linux ]] && id -g || print 1000 }

# $1 = dir (may be empty), remaining args = extra `docker build` flags
_agent_build() {
  emulate -L zsh
  local dir=$(_agent_dir "$1") name=$(_agent_name "$1") hash uid gid
  shift
  hash=$(_agent_devcontainer_hash "$dir") || return 1
  uid=$(_agent_host_uid) gid=$(_agent_host_gid)
  local -a vargs
  vargs=(${(f)"$(_agent_build_version_args "$dir")"})
  docker build "$@" -t "$name" \
    --build-arg TZ="$AGENT_TZ" "${vargs[@]}" \
    --build-arg USER_UID="$uid" --build-arg USER_GID="$gid" \
    --label "agent.devcontainer-sha256=$hash" \
    --label "agent.user-uid=$uid" \
    "$dir/.devcontainer"
}

# $1 = dir, $2 = mode: normal (default) | setup
_agent_create() {
  emulate -L zsh
  local dir=$(_agent_dir "$1") name=$(_agent_name "$1") mode=${2:-normal}
  local flags out gn ge
  local -a mounts ports env_args

  if [[ $mode == setup ]]; then
    flags=""                      # prompts on, whatever devcontainer.json says
  else
    flags=$(_agent_shortcut_flags "$dir")
    # --mount, not -v: a ":" in the path would split a -v spec. .git itself is
    # mounted (read-write) so it is a mount point: otherwise `mv .git .git.x;
    # cp -a .git.x .git` inside would hand the host a writable copy with the
    # agent's hooks and config, and the two read-only overlays would sit in
    # the renamed directory, protecting nothing.
    mounts=(
      --mount "type=bind,src=$dir/.git,dst=/workspace/.git"
      --mount "type=bind,src=$dir/.devcontainer,dst=/workspace/.devcontainer,readonly"
      --mount "type=bind,src=$dir/.git/hooks,dst=/workspace/.git/hooks,readonly"
      --mount "type=bind,src=$dir/.git/config,dst=/workspace/.git/config,readonly"
    )
  fi

  out=$(_agent_port_args "$dir") || return 1
  ports=(${(f)out})

  # No .gitconfig is copied in (that was the VS Code attach), so pass the
  # identity. Only when set on the host.
  gn=$(git config --global user.name 2>/dev/null) || gn=
  ge=$(git config --global user.email 2>/dev/null) || ge=
  [[ -n $gn ]] && env_args+=(-e "GIT_AUTHOR_NAME=$gn" -e "GIT_COMMITTER_NAME=$gn")
  [[ -n $ge ]] && env_args+=(-e "GIT_AUTHOR_EMAIL=$ge" -e "GIT_COMMITTER_EMAIL=$ge")

  docker run -d --name "$name" \
    --label "agent.mode=$mode" \
    --cap-add NET_ADMIN --cap-add NET_RAW \
    --mount "type=bind,src=$dir,dst=/workspace" \
    "${mounts[@]}" \
    -v "$name-config":/home/node/.claude \
    -v "$name-history":/commandhistory \
    "${ports[@]}" \
    -e CLAUDE_CONFIG_DIR=/home/node/.claude \
    -e NODE_OPTIONS=--max-old-space-size=4096 \
    -e POWERLEVEL9K_DISABLE_GITSTATUS=true \
    -e "CLAUDE_SHORTCUT_FLAGS=$flags" \
    -e DISABLE_ERROR_REPORTING=1 \
    -e DISABLE_TELEMETRY=1 \
    -e "AGENT_CONTAINER_NAME=$name" \
    "${env_args[@]}" \
    -w /workspace \
    "$name" sleep infinity >/dev/null
}

_agent_running() {
  emulate -L zsh
  [[ $(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null) == true ]]
}

_agent_container_mode() {
  emulate -L zsh
  docker container inspect -f '{{index .Config.Labels "agent.mode"}}' "$1" 2>/dev/null
}

# Host path mounted at /workspace in an existing container (empty if none).
_agent_container_workspace() {
  emulate -L zsh
  docker container inspect -f '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' "$1" 2>/dev/null
}

# Same folder name, different folder: refuse rather than attach an agent to
# the wrong tree (and share its sign-in and history volumes).
_agent_check_workspace() {
  emulate -L zsh
  local dir=$1 name=$2 src
  src=$(_agent_container_workspace "$name")
  [[ -z $src || $src == $dir ]] && return 0
  print -u2 "agent: container $name already exists for $src, not $dir (same folder name)."
  print -u2 "agent: rename one of the folders, or remove that container (docker rm -f $name) if it is stale."
  return 1
}

# 0 when the image exists and .devcontainer differs from what it was built
# from (or the image carries no hash). Used to gate rebuild/recreate: in
# setup mode the agent can edit .devcontainer, and a committed edit leaves
# `git status` clean — the image label is the last state a human built from.
_agent_changed_since_build() {
  emulate -L zsh
  local dir=$1 name=$2 built now
  docker image inspect "$name" >/dev/null 2>&1 || return 1
  built=$(docker image inspect -f '{{index .Config.Labels "agent.devcontainer-sha256"}}' "$name" 2>/dev/null)
  now=$(_agent_devcontainer_hash "$dir") || return 1
  [[ $built != $now ]]
}

# Show what changed under .devcontainer and ask. $3 = the action named in
# the question. Returns 1 when declined.
_agent_review_gate() {
  emulate -L zsh
  local dir=$1 name=$2 action=$3 changes reply
  changes=$(cd "$dir" && git status --porcelain -- .devcontainer 2>/dev/null)
  if [[ -z $changes ]] && ! _agent_changed_since_build "$dir" "$name"; then
    return 0
  fi
  print -u2 "agent: .devcontainer differs from the last build — the $action uses whatever is in there."
  if [[ -n $changes ]]; then
    print -u2 "agent: uncommitted changes (git status --porcelain -- .devcontainer):"
    print -u2 -r -- "$changes"
  else
    print -u2 "agent: (tree is clean: the changes are committed; review \`git log -p -- .devcontainer\`)"
  fi
  # read -r, not read -q: -q needs a terminal, and this must also work piped.
  read -r "reply?agent: reviewed — $action anyway? [y/N] " || reply=n
  [[ $reply == [yY]* ]] && return 0
  print -u2 "agent: aborted"
  return 1
}

# Firewall rules vanish whenever the container (re)starts, and a container
# started by hand never had them. Decide by the actual state — the OUTPUT
# policy — never by how the container got here.
_agent_firewall() {
  emulate -L zsh
  local name=$1 out
  docker exec -u root "$name" iptables -S OUTPUT 2>/dev/null | grep -q -- '-P OUTPUT DROP' && return 0
  print "agent: applying firewall in $name"
  if ! out=$(docker exec -u root "$name" /usr/local/bin/init-firewall.sh 2>&1); then
    tail -n 15 <<< "$out" >&2
    print -u2 "agent: firewall failed, stopping $name"
    docker stop "$name" >/dev/null
    return 1
  fi
}

# Warn (never block) when .devcontainer differs from what the image was built
# from. Changes there only take effect at a rebuild — which is exactly when
# they must have been reviewed.
_agent_drift_warn() {
  emulate -L zsh
  local dir=$1 name=$2 built now
  built=$(docker image inspect -f '{{index .Config.Labels "agent.devcontainer-sha256"}}' "$name" 2>/dev/null)
  now=$(_agent_devcontainer_hash "$dir") || return 0
  if [[ ! $built =~ '^[0-9a-f]{64}$' ]]; then
    print -u2 "agent: WARNING: image $name carries no .devcontainer hash (built outside agent?) — agent-rebuild labels it"
  elif [[ $built != $now ]]; then
    print -u2 "agent: WARNING: .devcontainer changed since the last build — review \`git diff -- .devcontainer\`, then agent-rebuild"
  fi
  # Linux only: an image built for another uid cannot write the bind mount.
  local want=$(_agent_host_uid) have
  if [[ $want != 1000 ]]; then
    have=$(docker image inspect -f '{{index .Config.Labels "agent.user-uid"}}' "$name" 2>/dev/null)
    [[ $have == $want ]] || print -u2 "agent: WARNING: image $name was built for uid ${have:-1000 (default)}, your uid is $want — the agent cannot write /workspace; agent-rebuild fixes it"
  fi
}

_agent_setup_banner() {
  emulate -L zsh
  print -u2 "agent: ================= SETUP MODE ================="
  print -u2 "agent: .devcontainer, .git/config and .git/hooks are WRITABLE from inside,"
  print -u2 "agent: and the cc/ccw shortcuts prompt for every permission."
  print -u2 "agent: Use it for /init or scripts/new-project.sh only. Afterwards: review"
  print -u2 "agent: \`git diff -- .devcontainer\`, then agent-rebuild. Plain \`agent\` will"
  print -u2 "agent: refuse to attach to this container until you do."
  print -u2 "agent: =============================================="
}

agent() {
  emulate -L zsh
  local use_tmux=1 mode=normal
  while [[ $1 == --* ]]; do
    case $1 in
      --no-tmux) use_tmux=0 ;;
      --setup) mode=setup ;;
      *) print -u2 "agent: unknown option $1 (known: --no-tmux, --setup)"; return 2 ;;
    esac
    shift
  done

  _agent_check "$1" "$mode" || return 1
  local dir=$(_agent_dir "$1") name=$(_agent_name "$1") current
  [[ $mode == setup ]] && _agent_setup_banner

  # Build / create / start only what's missing, so manual steps are fine.
  docker image inspect "$name" >/dev/null 2>&1 || _agent_build "$dir" || return 1

  if docker container inspect "$name" >/dev/null 2>&1; then
    _agent_check_workspace "$dir" "$name" || return 1
    current=$(_agent_container_mode "$name")
    if [[ $mode == normal && $current == setup ]]; then
      print -u2 "agent: $name was created in setup mode (writable .devcontainer and .git/config, prompts on)."
      print -u2 "agent: review \`git diff -- .devcontainer\` in $dir, then run agent-rebuild${1:+ $1}."
      print -u2 "agent: (agent --setup${1:+ $1} re-attaches to it meanwhile.)"
      return 1
    fi
    if [[ $mode == setup && $current != setup ]]; then
      if _agent_running "$name"; then
        print -u2 "agent: $name is a running normal-mode container — agent-stop${1:+ $1} first, then agent --setup${1:+ $1} again"
        return 1
      fi
      print "agent: replacing the stopped normal-mode container $name with a setup-mode one (volumes are kept)"
      docker rm -f "$name" >/dev/null || return 1
      _agent_create "$dir" setup || return 1
    fi
  else
    _agent_create "$dir" "$mode" || return 1
  fi

  _agent_running "$name" || docker start "$name" >/dev/null || return 1

  _agent_firewall "$name" || return 1
  _agent_drift_warn "$dir" "$name"

  # tmux if the image has it (sessions survive closing the tab), else plain zsh.
  if (( use_tmux )) && docker exec "$name" sh -c 'command -v tmux' >/dev/null 2>&1; then
    docker exec -it "$name" tmux new-session -A -s main
  else
    (( use_tmux )) && print -u2 "agent: no tmux in the image, opening zsh (closing this tab ends whatever runs in it)"
    docker exec -it "$name" zsh
  fi
}

agent-setup() { emulate -L zsh; agent --setup "$@" }
agent-shell() { emulate -L zsh; agent --no-tmux "$@" }

agent-rebuild() {
  emulate -L zsh
  _agent_check "$1" || return 1
  local dir=$(_agent_dir "$1") name=$(_agent_name "$1")
  print "agent: rebuilding $name from $dir/.devcontainer — review \`git diff -- .devcontainer\` first; the image runs whatever is in there."
  if docker container inspect "$name" >/dev/null 2>&1; then
    _agent_check_workspace "$dir" "$name" || return 1
  fi
  _agent_review_gate "$dir" "$name" rebuild || return 1
  # --no-cache: otherwise the cached layer keeps the old Claude Code ("latest" at first build)
  _agent_build "$dir" --pull --no-cache || return 1
  docker rm -f "$name" >/dev/null 2>&1
  _agent_create "$dir" normal || return 1
  print "agent: rebuilt $name; run: agent${1:+ $1}"
}

agent-recreate() {
  emulate -L zsh
  _agent_check "$1" || return 1
  local dir=$(_agent_dir "$1") name=$(_agent_name "$1")
  if ! docker image inspect "$name" >/dev/null 2>&1; then
    print -u2 "agent: no image $name yet — run agent${1:+ $1}"
    return 1
  fi
  if docker container inspect "$name" >/dev/null 2>&1; then
    _agent_check_workspace "$dir" "$name" || return 1
  fi
  # The new container reads CLAUDE_SHORTCUT_FLAGS and agent-ports from
  # .devcontainer, which a setup-mode agent could have edited.
  _agent_review_gate "$dir" "$name" recreate || return 1
  docker rm -f "$name" >/dev/null 2>&1
  _agent_create "$dir" normal || return 1
  print "agent: recreated $name; run: agent${1:+ $1}"
}

agent-stop()  { emulate -L zsh; docker stop "$(_agent_name "$1")" >/dev/null }
agent-ports() { emulate -L zsh; docker port "$(_agent_name "$1")" }
