# agent-sandbox.zsh: run Claude Code in a per-project Docker container — plain Docker
# from the host, no devcontainer CLI, no VS Code attach.
#
# AGENT_SANDBOX_VERSION=1.7.0
#
# Source this from ~/.zshrc (`scripts/sync-harness.sh --install-shell` copies
# it to ~/.config/zsh/agent-sandbox.zsh and prints the line). Keep the installed copy
# OUTSIDE any folder an agent can write to — a project, the boilerplate
# checkout, a dotfiles repo you run Claude in — and never symlink it into a
# repo: this file decides what the container can see, so whoever can edit it
# controls the next `agent-sandbox` you type. Update it only through the install step,
# which shows the diff first.
#
#   agent-sandbox --version           version this shell loaded, and from where
#   agent-sandbox [--no-tmux] [dir]   build/create/start whatever is missing,
#                                     make sure the firewall is active, attach
#                                     to tmux inside (plain zsh if the image
#                                     has no tmux, or with --no-tmux)
#   agent-sandbox --setup [dir]       one-time SETUP container: no read-only
#   agent-sandbox-setup [dir]         mounts, permission prompts forced on.
#                                     For /init and the detach script. Plain
#                                     `agent-sandbox` refuses to attach to it
#                                     afterwards — review, then
#                                     agent-sandbox-rebuild.
#   agent-sandbox-rebuild [dir]       fresh base image + newest Claude Code,
#                                     new container. Shows what changed
#                                     in .devcontainer since the last
#                                     build, without git, and asks first.
#   agent-sandbox-recreate [dir]      new container from the existing image
#                                     (after env, port, read-only mount or .git/config
#                                     changes), no build
#   agent-sandbox-stop [dir]          stop the container (sign-in and history
#                                     are kept)
#   agent-sandbox-ports [dir]         host ports published for the container
#   agent-sandbox-check [-q] [dir]    the host-side checks alone, no Docker:
#                                     commondir redirect, unlisted nested
#                                     repositories (exit 1), unfinished
#                                     rebase (warning). Run it before git
#                                     on the host while a container exists;
#                                     -q prints only findings.
#   agent-sandbox-shell [dir]         plain zsh, no tmux (same as
#                                     agent-sandbox --no-tmux)
#
# Names: image, container and volumes are claude-<folder name>, lowercased,
# anything outside [a-z0-9_.-] replaced by "-". A container or image created
# by hand under that name is picked up as it is. Two projects with the same
# folder name share the name: `agent-sandbox` refuses to attach when the existing
# container's /workspace is another folder (rename one of them).
#
# What the container gets, and nothing else:
#   - the project folder at /workspace, read-write — with .devcontainer,
#     .vscode, .git/hooks, .git/config and .git/commondir mounted read-only
#     on top (normal mode), so an agent cannot change what the next rebuild
#     runs, what the editor runs on open, what git runs on the host, or
#     where git pushes. .git itself is also a (read-write) mount so it
#     cannot be renamed away and replaced by a writable copy — a parent
#     directory of a mount point can be renamed, a mount point cannot.
#     .git/commondir is a placeholder holding "." that `agent-sandbox` creates: with
#     it read-only, git cannot be redirected to another config and hooks
#     directory. .vscode is created empty when missing.
#   - nested repositories must be listed in .devcontainer/agent-sandbox-nested-repos
#     (a submodule entry would make the host's git read their config);
#     `agent-sandbox` refuses to attach when an unlisted one exists. Registered
#     submodules keep their config under .git/modules/, which is mounted
#     read-only per file; linked worktrees keep a per-worktree commondir
#     under .git/worktrees/, which `agent-sandbox` verifies says "../..".
#     Caveat: git rewrites .git/config by renaming a new file over it, so
#     after a host-side `git remote add`, `git config` or `push -u` the
#     container still sees the OLD inode — `agent-sandbox-recreate`. Docker
#     Desktop has also been seen to drop that mount entirely on a restart
#     while `docker inspect` still lists it, so every attach reads the
#     container's own /proc/1/mountinfo and refuses when a read-only path
#     is missing or writable.
#   - two named volumes: <name>-config (/home/node/.claude: sign-in, memory,
#     sessions) and <name>-history (/commandhistory)
#   - the environment devcontainer.json's containerEnv sets (keep the two in
#     step), the author identity from the host's global git config (env vars
#     — they win over a per-repo user.name/email), the Claude Code telemetry
#     opt-outs, and AGENT_SANDBOX_CONTAINER_NAME so commands inside can print exact
#     `docker port` hints
#   - NET_ADMIN/NET_RAW for the firewall; never --privileged, --network host,
#     the Docker socket, ~/.ssh, SSH_AUTH_SOCK or any other host path
#   - ports listed in .devcontainer/agent-sandbox-ports, published on 127.0.0.1 with
#     an ephemeral host port (`agent-sandbox-ports` shows the mapping)
#
# Labels: the image carries a sha256 of the .devcontainer directory at build
# time (agent-sandbox.devcontainer-sha256 — `agent-sandbox` warns when it no longer matches),
# the container records which mode created it (agent-sandbox.mode=normal|setup).
#
# Host state outside the repo: ${XDG_CACHE_HOME:-~/.cache}/agent-sandbox/<name>/
# holds a copy of .devcontainer from the last build and, after `agent-sandbox
# --setup`, copies of .git/config and .git/hooks from before the setup
# container existed. The review gate diffs against these, so it never has
# to run git inside the project: the repo's own git config and hooks are
# attacker-controlled by assumption, and `git status` would execute them
# (core.fsmonitor). The only git call in this file is `git config --global`,
# run from /.
#
# Not covered by any mount: the rest of .git is writable, so the container
# can leave an interactive rebase stopped before an `exec` line, and `git
# rebase --continue` (or --skip) on the host runs that line as you.
# `agent-sandbox` and the review gate warn when .git/rebase-merge,
# .git/rebase-apply or .git/sequencer exists (checked with the shell). Abort
# a rebase you did not start; never continue it.
#
# Requires zsh 5.9 or newer (macOS ships it; on Linux install zsh — bash
# users get a shim from `sync-harness.sh --install-shell`) and `docker` on
# PATH. Sourcing defines functions and the one variable below; nothing else.
#
# Linux hosts: native Docker Engine shows the repo with the host user's uid,
# so the image is built with USER_UID/USER_GID = your ids (Docker Desktop
# maps ownership itself and keeps the defaults). The image is labelled with
# the uid it was built for; `agent-sandbox` warns when it no longer matches.

# Which copy this shell sourced, and its version, for `agent-sandbox --version`.
# Recorded as two functions, not variables: sourcing adds no globals.
() {
  local f=${${(%):-%x}:A} v
  v=${${(M)${(f)"$(<$f)"}:#\# AGENT_SANDBOX_VERSION=*}[1]#*=}
  functions[_agent_sandbox_loaded_file]="print -r -- ${(q)f}"
  functions[_agent_sandbox_loaded_version]="print -r -- ${(q)v}"
}

typeset -g AGENT_SANDBOX_TZ=${AGENT_SANDBOX_TZ:-${TZ:-Europe/Berlin}}   # container time zone

_agent_sandbox_dir() { emulate -L zsh; print -r -- ${${1:-$PWD}:A} }

_agent_sandbox_name() {
  emulate -L zsh
  local dir=$(_agent_sandbox_dir "$1")
  local n=${(L)dir:t}
  print -r -- "claude-${n//[^a-z0-9_.-]/-}"
}

# Refuse folders that would make docker create missing bind sources on the
# host (a bind of a nonexistent path appears as a new root-owned directory).
# $2 = setup: only the Dockerfile is required. Setup mode mounts nothing
# below the project folder, and the detach flow (scripts/new-project.sh)
# deletes and re-inits .git — which the read-only mounts make impossible anyway.
_agent_sandbox_check() {
  emulate -L zsh
  local dir=$(_agent_sandbox_dir "$1")
  if [[ $dir == *,* ]]; then
    print -u2 "agent-sandbox: $dir contains a comma, which docker's --mount syntax cannot carry; rename the folder"
    return 1
  fi
  if [[ ! -f $dir/.devcontainer/Dockerfile ]]; then
    print -u2 "agent-sandbox: $dir has no .devcontainer/Dockerfile"
    return 1
  fi
  [[ $2 == setup ]] && return 0
  if [[ ! -f $dir/.git/config || ! -d $dir/.git/hooks ]]; then
    print -u2 "agent-sandbox: $dir needs .git/config and .git/hooks (a git repository) for the read-only mounts"
    return 1
  fi
  # The commondir placeholder: "." with no newline (git 2.39 rejects a
  # trailing newline; an empty file breaks every git command). Created
  # here, on the host, so the read-only mount has a source.
  if [[ ! -e $dir/.git/commondir ]]; then
    printf '.' > "$dir/.git/commondir" || { print -u2 "agent-sandbox: cannot create $dir/.git/commondir"; return 1 }
    print "agent-sandbox: created $dir/.git/commondir placeholder (\".\"); it is mounted read-only"
  fi
  _agent_sandbox_check_commondir "$dir" || return 1
  [[ -d $dir/.vscode ]] || mkdir -p "$dir/.vscode" || return 1
  return 0
}

# sha256 over the sorted file list + contents of .devcontainer. macOS ships
# shasum, Linux sha256sum; both print "<hash>  -" for stdin.
_agent_sandbox_devcontainer_hash() {
  emulate -L zsh
  local dir=$(_agent_sandbox_dir "$1") f
  local -a sum
  if (( $+commands[shasum] )); then sum=(shasum -a 256)
  elif (( $+commands[sha256sum] )); then sum=(sha256sum)
  else print -u2 "agent-sandbox: need shasum or sha256sum on PATH"; return 1
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
_agent_sandbox_json_line_value() {
  emulate -L zsh
  { grep -m1 -E "^[[:space:]]*\"$2\":" "$1" 2>/dev/null || true } \
    | sed -E 's/^[^:]*:[[:space:]]*"([^"]*)".*$/\1/'
}

# CLAUDE_SHORTCUT_FLAGS from devcontainer.json. Only empty or space-separated
# --long-flags pass; anything else (a quote, a path, `;`) is a warning and
# the shortcuts run with prompts on.
_agent_sandbox_shortcut_flags() {
  emulate -L zsh
  local dir=$(_agent_sandbox_dir "$1") flags
  flags=$(_agent_sandbox_json_line_value "$dir/.devcontainer/devcontainer.json" CLAUDE_SHORTCUT_FLAGS)
  if [[ $flags =~ '^(--[a-z0-9-]+( |$))*$' ]]; then
    print -r -- "$flags"
    return 0
  fi
  print -u2 "agent-sandbox: ignoring CLAUDE_SHORTCUT_FLAGS in devcontainer.json ('$flags'): only space-separated --long-flags are accepted; the shortcuts will prompt"
  print -r -- ""
}

# CLAUDE_CODE_VERSION build arg from devcontainer.json (devcontainer.json
# overrides the Dockerfile default there, so do the same here).
_agent_sandbox_build_version_args() {
  emulate -L zsh
  local dir=$(_agent_sandbox_dir "$1") v
  v=$(_agent_sandbox_json_line_value "$dir/.devcontainer/devcontainer.json" CLAUDE_CODE_VERSION)
  if [[ -n $v && $v =~ '^[A-Za-z0-9._-]+$' ]]; then
    print -r -- "--build-arg"
    print -r -- "CLAUDE_CODE_VERSION=$v"
  fi
}

# .devcontainer/agent-sandbox-ports → `-p 127.0.0.1::<port>` pairs, one token per
# line. One bad line rejects the whole file (and the create). The file sits
# under the read-only mount, so only the host side can change it.
_agent_sandbox_port_args() {
  emulate -L zsh
  local dir=$(_agent_sandbox_dir "$1") f line n=0
  f=$dir/.devcontainer/agent-sandbox-ports
  [[ -f $f ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    (( n++ ))
    line=${line%%#*}
    line=${line//[[:space:]]/}
    [[ -z $line ]] && continue
    if [[ $line != <1-65535> ]]; then
      print -u2 "agent-sandbox: $f:$n: not a port (1-65535): '$line' — fix the file; no ports published"
      return 1
    fi
    print -r -- "-p"
    print -r -- "127.0.0.1::$line"
  done < "$f"
}

# Per-project host state, outside anything the agent can write.
_agent_sandbox_state_dir() {
  emulate -L zsh
  print -r -- "${XDG_CACHE_HOME:-$HOME/.cache}/agent-sandbox/$1"
}

# Copy of .devcontainer as it was at the last build (what the image ran).
_agent_sandbox_snapshot_devcontainer() {
  emulate -L zsh
  local dir=$1 state=$(_agent_sandbox_state_dir "$2")
  mkdir -p "$state" && rm -rf "$state/devcontainer" && cp -R "$dir/.devcontainer" "$state/devcontainer"
}

# Copies of .git/config and .git/hooks from BEFORE a setup container, where
# both are writable. agent-sandbox-rebuild diffs the live files against them.
_agent_sandbox_snapshot_git() {
  emulate -L zsh
  local dir=$1 state=$(_agent_sandbox_state_dir "$2")
  mkdir -p "$state" && rm -rf "$state/setup-git-config" "$state/setup-git-hooks"
  [[ -f $dir/.git/config ]] && cp "$dir/.git/config" "$state/setup-git-config"
  [[ -d $dir/.git/hooks ]] && cp -R "$dir/.git/hooks" "$state/setup-git-hooks"
  return 0
}

# .git/commondir redirects git to another directory's config and hooks — a
# way around the read-only mounts that needs only a writable .git. A
# placeholder holding exactly "." (no newline) is harmless; anything else
# means the host must not run git in this repo until it is removed. Read
# with the shell, never with git.
_agent_sandbox_check_commondir() {
  emulate -L zsh
  local f=$1/.git/commondir w bad=0
  # Exactly one byte: $(<f) drops a trailing newline, and ".\n" breaks git
  # on 2.39 instead of being read as ".".
  if [[ -e $f ]] && ! [[ -f $f && "$(<"$f")" == "." && $(wc -c < "$f") -eq 1 ]]; then
    print -u2 "agent-sandbox: DANGER: $f exists and does not hold '.' — git on the host would read config and"
    print -u2 "agent-sandbox: hooks from the directory it names (core.fsmonitor there runs as you). Do not run git in"
    print -u2 "agent-sandbox: $1 until you have inspected and removed that file."
    bad=1
  fi
  # Linked worktrees (.claude/worktrees/<n>, ccw, claude --worktree) carry
  # their own commondir under .git/worktrees/<n>/, writable from inside.
  # git writes "../.." there; anything else redirects git run INSIDE that
  # worktree on the host (an editor, a shell prompt) to another config.
  for w in "$1"/.git/worktrees/*/commondir(N); do
    [[ "$(<"$w")" == "../.." ]] && continue
    print -u2 "agent-sandbox: DANGER: $w does not hold '../..' — git run inside that worktree on the host would read"
    print -u2 "agent-sandbox: config and hooks from the directory it names. Inspect and remove it before running git there."
    bad=1
  done
  return $bad
}

# An unfinished rebase, `git am` or cherry-pick/revert sequence recorded in
# .git (or in a linked worktree's git directory). All of these are writable
# from inside the container, and an interactive rebase's todo list can hold
# `exec` lines: `git rebase --continue` or `--skip` on the host runs them as
# the user. `git status` shows at most the next two todo lines, so a later
# `exec` is not visible there. Warns, never blocks: the user may have a
# rebase of their own in progress, so callers ignore the status (1 when
# something was found). Checked with the shell, never with git.
_agent_sandbox_warn_git_in_progress() {
  emulate -L zsh
  local dir=$1 p
  local -a found
  for p in "$dir"/.git/{rebase-merge,rebase-apply,sequencer}(N) "$dir"/.git/worktrees/*/{rebase-merge,rebase-apply,sequencer}(N); do
    found+=("${p#$dir/}")
  done
  (( $#found )) || return 0
  print -u2 "agent-sandbox: WARNING: an unfinished rebase, am or cherry-pick/revert sequence is recorded in $dir:"
  for p in "${found[@]}"; do print -u2 -r -- "agent-sandbox:   $p"; done
  print -u2 "agent-sandbox: the container can write these, and a rebase todo list can hold \`exec\` lines that"
  print -u2 "agent-sandbox: \`git rebase --continue\` or \`--skip\` runs on the host as you. If you did not start it on"
  print -u2 "agent-sandbox: the host, abort it (\`git rebase --abort\`, \`git am --abort\`, \`git cherry-pick --abort\`);"
  print -u2 "agent-sandbox: never continue it. Before continuing one of your own, read the todo file"
  print -u2 "agent-sandbox: (.git/rebase-merge/git-rebase-todo) for \`exec\` lines."
  return 1
}

# Nested repositories (a .git dir or file below the top level). A submodule
# entry in the index makes the host's `git status` read the nested repo's
# config, including core.fsmonitor. Worktrees the harness creates and
# node_modules are skipped. Prints one path per line.
_agent_sandbox_nested_repos() {
  emulate -L zsh
  # No -mindepth: it would skip the prune tests at depth 1 (node_modules, .git).
  find "$1" \( -path "$1/.git" -o -path "$1/.claude/worktrees" -o -path "$1/.worktrees" -o -name node_modules \) -prune -o -name .git -print 2>/dev/null
}

# Nested repositories not listed in .devcontainer/agent-sandbox-nested-repos (one
# path per line relative to the project root, naming the directory that
# holds the .git; zsh glob patterns allowed, e.g. audits/*; # comments).
# Prints the unlisted ones, one per line; returns 1 when there are any.
_agent_sandbox_unlisted_nested_repos() {
  emulate -L zsh
  local dir=$1 f=$1/.devcontainer/agent-sandbox-nested-repos line rel pat found=0
  local -a allow
  if [[ -f $f ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%%#*}; line=${line## }; line=${line%% }; line=${line%/}
      [[ -n $line ]] && allow+=("$line")
    done < "$f"
  fi
  for rel in ${(f)"$(_agent_sandbox_nested_repos "$dir")"}; do
    rel=${rel#$dir/}; rel=${rel%/.git}
    local ok=0
    for pat in "${allow[@]}"; do [[ $rel == ${~pat} ]] && { ok=1; break }; done
    (( ok )) || { print -r -- "$rel"; found=1 }
  done
  return $(( found ))
}

# Refuses (returns 1) when an unlisted nested repository exists: a submodule
# entry for it would make the host's git read its config (core.fsmonitor).
_agent_sandbox_check_nested_repos() {
  emulate -L zsh
  local dir=$1 unlisted
  if unlisted=$(_agent_sandbox_unlisted_nested_repos "$dir"); then
    # All listed. Still worth one line: a listed repository is trusted, and the
    # plain status/diff on the host spawn git in it unless told not to.
    # $2 = quiet leaves the line out (agent-sandbox-check -q).
    if [[ $2 != quiet && -n $(_agent_sandbox_nested_repos "$dir") ]] && ! grep -qE '^[[:space:]]*ignoreSubmodules[[:space:]]*=[[:space:]]*all' "$dir/.git/config" 2>/dev/null; then
      print -u2 "agent-sandbox: note: nested repositories are listed; never run git, a git prompt or an IDE inside them on the host. \`git config diff.ignoreSubmodules all\` prevents accidents from plain status/diff/commit only: \`git add .\` and a .gitmodules entry with ignore=none still run their config, so do not rely on it."
    fi
    return 0
  fi
  print -u2 "agent-sandbox: nested git repositories under $dir that .devcontainer/agent-sandbox-nested-repos does not list:"
  print -u2 -r -- "$unlisted" | sed 's/^/agent-sandbox:   /' >&2
  print -u2 "agent-sandbox: a submodule entry for one of them makes the host's git read its config (core.fsmonitor)."
  print -u2 "agent-sandbox: list the ones you expect in .devcontainer/agent-sandbox-nested-repos (on the host), or remove them."
  print -u2 "agent-sandbox: until then, do not run git in $dir on the host: \`git status\` and \`git add\` can run their config."
  if ! grep -qE '^[[:space:]]*ignoreSubmodules[[:space:]]*=[[:space:]]*all' "$dir/.git/config" 2>/dev/null; then
    print -u2 "agent-sandbox: (\`git config diff.ignoreSubmodules all\` prevents accidents from plain status/diff/commit only; \`git add .\` and a .gitmodules entry with ignore=none still run their config, so do not rely on it.)"
  fi
  return 1
}

# Host ids the container user should have: the real ones on Linux (native
# Docker Engine keeps host ownership on bind mounts), the Dockerfile default
# everywhere else (Docker Desktop maps ownership itself).
_agent_sandbox_host_uid() { emulate -L zsh; [[ $(uname -s) == Linux ]] && id -u || print 1000 }
_agent_sandbox_host_gid() { emulate -L zsh; [[ $(uname -s) == Linux ]] && id -g || print 1000 }

# $1 = dir (may be empty), remaining args = extra `docker build` flags
_agent_sandbox_build() {
  emulate -L zsh
  local dir=$(_agent_sandbox_dir "$1") name=$(_agent_sandbox_name "$1") hash uid gid
  shift
  hash=$(_agent_sandbox_devcontainer_hash "$dir") || return 1
  uid=$(_agent_sandbox_host_uid) gid=$(_agent_sandbox_host_gid)
  local -a vargs
  vargs=(${(f)"$(_agent_sandbox_build_version_args "$dir")"})
  docker build "$@" -t "$name" \
    --build-arg TZ="$AGENT_SANDBOX_TZ" "${vargs[@]}" \
    --build-arg USER_UID="$uid" --build-arg USER_GID="$gid" \
    --label "agent-sandbox.devcontainer-sha256=$hash" \
    --label "agent-sandbox.user-uid=$uid" \
    "$dir/.devcontainer" || return 1
  _agent_sandbox_snapshot_devcontainer "$dir" "$name"
}

# $1 = dir, $2 = mode: normal (default) | setup
_agent_sandbox_create() {
  emulate -L zsh
  local dir=$(_agent_sandbox_dir "$1") name=$(_agent_sandbox_name "$1") mode=${2:-normal}
  local flags out gn ge
  local -a mounts ports env_args

  if [[ $mode == setup ]]; then
    flags=""                      # prompts on, whatever devcontainer.json says
  else
    flags=$(_agent_sandbox_shortcut_flags "$dir")
    # --mount, not -v: a ":" in the path would split a -v spec. .git itself is
    # mounted (read-write) so it is a mount point: otherwise `mv .git .git.x;
    # cp -a .git.x .git` inside would hand the host a writable copy with the
    # agent's hooks and config, and the two read-only mounts would sit in
    # the renamed directory, protecting nothing.
    mounts=(
      --mount "type=bind,src=$dir/.git,dst=/workspace/.git"
      --mount "type=bind,src=$dir/.devcontainer,dst=/workspace/.devcontainer,readonly"
      --mount "type=bind,src=$dir/.vscode,dst=/workspace/.vscode,readonly"
      --mount "type=bind,src=$dir/.git/hooks,dst=/workspace/.git/hooks,readonly"
      --mount "type=bind,src=$dir/.git/config,dst=/workspace/.git/config,readonly"
      --mount "type=bind,src=$dir/.git/commondir,dst=/workspace/.git/commondir,readonly"
    )
    # Registered submodules: the host's git reads .git/modules/<n>/config for
    # each (core.fsmonitor included). Mount every existing one read-only;
    # a submodule added inside is covered from the next agent-sandbox-recreate on
    # (and its .git file must be listed in agent-sandbox-nested-repos anyway).
    local m
    for m in "$dir"/.git/modules/**/config(N.); do
      mounts+=(--mount "type=bind,src=$m,dst=/workspace/${m#$dir/},readonly")
    done
  fi

  out=$(_agent_sandbox_port_args "$dir") || return 1
  ports=(${(f)out})

  # No .gitconfig is copied in (that was the VS Code attach), so pass the
  # identity. Only when set on the host.
  # From /, so git never discovers (and reads) the project's own repository.
  gn=$(cd / && git config --global user.name 2>/dev/null) || gn=
  ge=$(cd / && git config --global user.email 2>/dev/null) || ge=
  [[ -n $gn ]] && env_args+=(-e "GIT_AUTHOR_NAME=$gn" -e "GIT_COMMITTER_NAME=$gn")
  [[ -n $ge ]] && env_args+=(-e "GIT_AUTHOR_EMAIL=$ge" -e "GIT_COMMITTER_EMAIL=$ge")

  docker run -d --name "$name" \
    --label "agent-sandbox.mode=$mode" \
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
    -e "AGENT_SANDBOX_CONTAINER_NAME=$name" \
    "${env_args[@]}" \
    -w /workspace \
    "$name" sleep infinity >/dev/null
}

_agent_sandbox_running() {
  emulate -L zsh
  [[ $(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null) == true ]]
}

_agent_sandbox_container_mode() {
  emulate -L zsh
  docker container inspect -f '{{index .Config.Labels "agent-sandbox.mode"}}' "$1" 2>/dev/null
}

# Host path mounted at /workspace in an existing container (empty if none).
_agent_sandbox_container_workspace() {
  emulate -L zsh
  docker container inspect -f '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' "$1" 2>/dev/null
}

# Same folder name, different folder: refuse rather than attach an agent to
# the wrong tree (and share its sign-in and history volumes).
_agent_sandbox_check_workspace() {
  emulate -L zsh
  local dir=$1 name=$2 src
  src=$(_agent_sandbox_container_workspace "$name")
  [[ -z $src || $src == $dir ]] && return 0
  print -u2 "agent-sandbox: container $name already exists for $src, not $dir (same folder name)."
  print -u2 "agent-sandbox: rename one of the folders, or remove that container (docker rm -f $name) if it is stale."
  return 1
}

# 0 when the image exists and .devcontainer differs from what it was built
# from (or the image carries no hash). Used to gate rebuild/recreate: in
# setup mode the agent can edit .devcontainer, and a committed edit leaves
# `git status` clean — the image label is the last state a human built from.
_agent_sandbox_changed_since_build() {
  emulate -L zsh
  local dir=$1 name=$2 built now
  docker image inspect "$name" >/dev/null 2>&1 || return 1
  built=$(docker image inspect -f '{{index .Config.Labels "agent-sandbox.devcontainer-sha256"}}' "$name" 2>/dev/null)
  now=$(_agent_sandbox_devcontainer_hash "$dir") || return 1
  [[ $built != $now ]]
}

# What a rebuild or recreate would pick up that no human has reviewed:
# .devcontainer versus the last build's copy, .git/config and .git/hooks
# versus the pre-setup copies, nested repositories, a commondir redirect.
# Nothing here runs git. $3 = the action named in the question. Returns 1
# when declined or when the commondir check fails.
_agent_sandbox_review_gate() {
  emulate -L zsh
  local dir=$1 name=$2 action=$3 state=$(_agent_sandbox_state_dir "$2") reply ask=0 out
  _agent_sandbox_check_commondir "$dir" || return 1
  _agent_sandbox_warn_git_in_progress "$dir"

  if _agent_sandbox_changed_since_build "$dir" "$name"; then
    ask=1
    print -u2 "agent-sandbox: .devcontainer differs from the image's last build — the $action uses whatever is in there."
    if [[ -d $state/devcontainer ]]; then
      print -u2 "agent-sandbox: changes since that build (last build → now):"
      diff -ru "$state/devcontainer" "$dir/.devcontainer" 2>&1 | sed 's/^/agent-sandbox:   /' >&2
    else
      print -u2 "agent-sandbox: (no build copy in $state — the image was built outside agent-sandbox; compare by hand before answering)"
    fi
  fi

  if [[ -f $state/setup-git-config || -d $state/setup-git-hooks ]]; then
    out=""
    [[ -f $state/setup-git-config ]] && out+=$(diff -u "$state/setup-git-config" "$dir/.git/config" 2>&1)
    [[ -d $state/setup-git-hooks ]] && out+=$(diff -ru "$state/setup-git-hooks" "$dir/.git/hooks" 2>&1)
    if [[ -n $out ]]; then
      ask=1
      print -u2 "agent-sandbox: .git/config or .git/hooks changed while a setup container existed (before setup → now):"
      print -u2 -r -- "$out" | sed 's/^/agent-sandbox:   /' >&2
      print -u2 "agent-sandbox: the host's git runs what these name (core.fsmonitor, core.hooksPath, hooks)."
    fi
  fi

  _agent_sandbox_check_nested_repos "$dir" || return 1

  (( ask )) || return 0
  # read -r, not read -q: -q needs a terminal, and this must also work piped.
  read -r "reply?agent-sandbox: reviewed — $action anyway? [y/N] " || reply=n
  [[ $reply == [yY]* ]] || { print -u2 "agent-sandbox: aborted"; return 1 }
  rm -rf "$state/setup-git-config" "$state/setup-git-hooks"   # reviewed
  return 0
}

# Firewall rules vanish whenever the container (re)starts, and a container
# started by hand never had them. Decide by the actual state — the OUTPUT
# policy — never by how the container got here.
_agent_sandbox_firewall() {
  emulate -L zsh
  local name=$1 out
  # Both the DROP policy and the allowlist rule: a first start that failed
  # leaves a loopback-only DROP table behind (init-firewall.sh's exit trap),
  # which must count as "not applied".
  out=$(docker exec -u root "$name" iptables -S OUTPUT 2>/dev/null)
  [[ $out == *'-P OUTPUT DROP'* && $out == *'--match-set allowed-domains'* ]] && return 0
  print "agent-sandbox: applying firewall in $name"
  if ! out=$(docker exec -u root "$name" /usr/local/bin/init-firewall.sh 2>&1); then
    tail -n 15 <<< "$out" >&2
    print -u2 "agent-sandbox: firewall failed, stopping $name"
    docker stop "$name" >/dev/null
    return 1
  fi
}

# Warn (never block) when .devcontainer differs from what the image was built
# from. Changes there only take effect at a rebuild — which is exactly when
# they must have been reviewed.
_agent_sandbox_drift_warn() {
  emulate -L zsh
  local dir=$1 name=$2 built now
  built=$(docker image inspect -f '{{index .Config.Labels "agent-sandbox.devcontainer-sha256"}}' "$name" 2>/dev/null)
  now=$(_agent_sandbox_devcontainer_hash "$dir") || return 0
  if [[ ! $built =~ '^[0-9a-f]{64}$' ]]; then
    print -u2 "agent-sandbox: WARNING: image $name carries no .devcontainer hash (built outside agent-sandbox?) — agent-sandbox-rebuild labels it"
  elif [[ $built != $now ]]; then
    print -u2 "agent-sandbox: WARNING: .devcontainer changed since the last build — run agent-sandbox-rebuild: it shows the diff (without git) and asks before building"
  fi
  # Linux only: an image built for another uid cannot write the bind mount.
  local want=$(_agent_sandbox_host_uid) have
  if [[ $want != 1000 ]]; then
    have=$(docker image inspect -f '{{index .Config.Labels "agent-sandbox.user-uid"}}' "$name" 2>/dev/null)
    [[ $have == $want ]] || print -u2 "agent-sandbox: WARNING: image $name was built for uid ${have:-1000 (default)}, your uid is $want — the agent cannot write /workspace; agent-sandbox-rebuild fixes it"
  fi
}

_agent_sandbox_setup_banner() {
  emulate -L zsh
  print -u2 "agent-sandbox: ================= SETUP MODE ================="
  print -u2 "agent-sandbox: .devcontainer, .git/config and .git/hooks are WRITABLE from inside,"
  print -u2 "agent-sandbox: and the cc/ccw shortcuts prompt for every permission."
  print -u2 "agent-sandbox: Use it for /init or scripts/new-project.sh only. agent-sandbox-rebuild afterwards"
  print -u2 "agent-sandbox: shows every change to .devcontainer, .git/config and .git/hooks made"
  print -u2 "agent-sandbox: meanwhile and asks before building. Plain \`agent-sandbox\` refuses to attach to"
  print -u2 "agent-sandbox: this container until then. Avoid running git in the repo on the host"
  print -u2 "agent-sandbox: before that review: its config and hooks are what the agent could edit."
  print -u2 "agent-sandbox: =============================================="
}

# Container paths _agent_sandbox_create mounts read-only in normal mode,
# one per line. $1 = dir.
_agent_sandbox_ro_paths() {
  emulate -L zsh
  local dir=$1 m
  print -l /workspace/.devcontainer /workspace/.vscode /workspace/.git/hooks \
    /workspace/.git/config /workspace/.git/commondir
  for m in "$dir"/.git/modules/**/config(N.); do
    print -r -- "/workspace/${m#$dir/}"
  done
}

# Checks the read-only mounts from inside the running container: `docker
# inspect` keeps listing a mount the container no longer has (seen with
# Docker Desktop after the host replaced .git/config by rename), so only
# the container's own mount table counts. Returns 1 when a path is not
# mounted or mounted writable. $1 = dir, $2 = name, $3 = the [dir] argument
# as the user typed it (for the hint).
_agent_sandbox_verify_mounts() {
  emulate -L zsh
  local dir=$1 name=$2 arg=$3 info line p key opts
  local -a f bad
  local -A opts_of
  if ! info=$(docker exec "$name" cat /proc/1/mountinfo 2>/dev/null) || [[ -z $info ]]; then
    print -u2 "agent-sandbox: cannot read the mount table inside $name, so the read-only mounts are unverified; not attaching"
    return 1
  fi
  # Field 5 is the mount point (space, tab, newline and backslash escaped as
  # octal), field 6 the per-mount options. A later line is mounted on top.
  for line in ${(f)info}; do
    f=(${=line})
    opts_of[${f[5]}]=${f[6]}
  done
  for p in ${(f)"$(_agent_sandbox_ro_paths "$dir")"}; do
    key=${p//\\/\\134}; key=${key// /\\040}; key=${key//$'\t'/\\011}
    opts=${opts_of[$key]}
    if [[ -z $opts ]]; then
      bad+=("$p (not mounted)")
    elif [[ ,$opts, != *,ro,* ]]; then
      bad+=("$p (mounted writable)")
    fi
  done
  (( $#bad )) || return 0
  print -u2 "agent-sandbox: read-only protection missing inside $name:"
  for p in $bad; do print -u2 "agent-sandbox:   $p"; done
  print -u2 "agent-sandbox: the agent could change git config or hooks that the host's git and VS Code run."
  if [[ ${(j: :)bad} == *"/workspace/.git/config (not mounted)"* ]]; then
    # Docker Desktop binds a single file by inode; git rewrites .git/config
    # via a lock file and rename, which leaves the container's mount behind.
    print -u2 "agent-sandbox: usual cause: a git command on the HOST rewrote .git/config (git init, git remote add,"
    print -u2 "agent-sandbox: git push -u, git branch -u, git config <key> <value>), which detaches the file mount."
  fi
  print -u2 "agent-sandbox: not attaching. Run agent-sandbox-recreate${arg:+ $arg} (sign-in and history are kept),"
  print -u2 "agent-sandbox: and check .git/config and .git/hooks for changes you did not make."
  return 1
}

# Version this shell loaded, plus a note when the file on disk has changed
# since (reinstalled, but this shell still runs the old functions).
_agent_sandbox_version() {
  emulate -L zsh
  local file=$(_agent_sandbox_loaded_file) loaded=$(_agent_sandbox_loaded_version) now
  now=$(grep -m1 -E '^# AGENT_SANDBOX_VERSION=' "$file" 2>/dev/null | cut -d= -f2)
  print -r -- "agent-sandbox.zsh ${loaded:-?} (loaded from $file)"
  if [[ $now != "$loaded" ]]; then
    print -r -- "agent-sandbox: the file there is now ${now:-missing} — open a new shell (or source ~/.zshrc) to load it"
  fi
  if [[ $(whence -w git) != "git: function" ]]; then
    print -r -- "agent-sandbox: git init guard inactive here: $(whence -w git) takes precedence"
  elif [[ $functions[git] != *AGENT_SANDBOX_GIT_INIT_GUARD* ]]; then
    print -r -- "agent-sandbox: git init guard inactive here: another git function replaced it (see: whence -v git)"
  fi
}

agent-sandbox() {
  emulate -L zsh
  local use_tmux=1 mode=normal
  while [[ $1 == --* ]]; do
    case $1 in
      --no-tmux) use_tmux=0 ;;
      --setup) mode=setup ;;
      --version) _agent_sandbox_version; return ;;
      *) print -u2 "agent-sandbox: unknown option $1 (known: --no-tmux, --setup, --version)"; return 2 ;;
    esac
    shift
  done

  _agent_sandbox_check "$1" "$mode" || return 1
  local dir=$(_agent_sandbox_dir "$1") name=$(_agent_sandbox_name "$1") current
  _agent_sandbox_check_commondir "$dir" || return 1
  _agent_sandbox_warn_git_in_progress "$dir"
  _agent_sandbox_check_nested_repos "$dir" || return 1
  [[ $mode == setup ]] && _agent_sandbox_setup_banner

  # Build / create / start only what's missing, so manual steps are fine.
  docker image inspect "$name" >/dev/null 2>&1 || _agent_sandbox_build "$dir" || return 1

  if docker container inspect "$name" >/dev/null 2>&1; then
    _agent_sandbox_check_workspace "$dir" "$name" || return 1
    current=$(_agent_sandbox_container_mode "$name")
    if [[ $mode == normal && $current == setup ]]; then
      print -u2 "agent-sandbox: $name was created in setup mode (writable .devcontainer and .git/config, prompts on)."
      print -u2 "agent-sandbox: run agent-sandbox-rebuild${1:+ $1}: it shows what changed in .devcontainer, .git/config and .git/hooks and asks."
      print -u2 "agent-sandbox: (agent-sandbox --setup${1:+ $1} re-attaches to it meanwhile.)"
      return 1
    fi
    if [[ $mode == setup && $current != setup ]]; then
      if _agent_sandbox_running "$name"; then
        print -u2 "agent-sandbox: $name is a running normal-mode container — agent-sandbox-stop${1:+ $1} first, then agent-sandbox --setup${1:+ $1} again"
        return 1
      fi
      print "agent-sandbox: replacing the stopped normal-mode container $name with a setup-mode one (volumes are kept)"
      docker rm -f "$name" >/dev/null || return 1
      _agent_sandbox_snapshot_git "$dir" "$name"
      _agent_sandbox_create "$dir" setup || return 1
    fi
  else
    [[ $mode == setup ]] && _agent_sandbox_snapshot_git "$dir" "$name"
    _agent_sandbox_create "$dir" "$mode" || return 1
  fi

  _agent_sandbox_running "$name" || docker start "$name" >/dev/null || return 1

  # Setup mode has no read-only mounts by design; it warns on its own.
  if [[ $mode == normal ]]; then
    _agent_sandbox_verify_mounts "$dir" "$name" "$1" || return 1
  fi
  _agent_sandbox_firewall "$name" || return 1
  _agent_sandbox_drift_warn "$dir" "$name"

  # docker exec passes no locale and sets TERM=xterm. Without a UTF-8
  # locale the tmux client replaces every non-ASCII character with "_";
  # C.UTF-8 is the one UTF-8 locale the image always has.
  local -a env=(-e LANG=C.UTF-8 -e TERM=xterm-256color)
  [[ -n $COLORTERM ]] && env+=(-e COLORTERM="$COLORTERM")

  # tmux if the image has it (sessions survive closing the tab), else plain zsh.
  if (( use_tmux )) && docker exec "$name" sh -c 'command -v tmux' >/dev/null 2>&1; then
    docker exec -it "${env[@]}" "$name" tmux new-session -A -s main
  else
    (( use_tmux )) && print -u2 "agent-sandbox: no tmux in the image, opening zsh (closing this tab ends whatever runs in it)"
    docker exec -it "${env[@]}" "$name" zsh
  fi
}

agent-sandbox-setup() { emulate -L zsh; agent-sandbox --setup "$@" }
agent-sandbox-shell() { emulate -L zsh; agent-sandbox --no-tmux "$@" }

# Removing the container kills everything running in it. When Claude Code
# is still running there, say so and ask (default No). Conversations are on
# the config volume, so `claude --continue` resumes the last one; whatever
# was mid-run is lost. $1 = name, $2 = action named in the question.
_agent_sandbox_confirm_no_live_session() {
  emulate -L zsh
  local name=$1 action=$2 reply
  [[ $(docker container inspect -f '{{.State.Running}}' "$name" 2>/dev/null) == true ]] || return 0
  docker exec "$name" pgrep -x claude >/dev/null 2>&1 || return 0
  print -u2 "agent-sandbox: Claude Code is still running in $name. The $action removes the container,"
  print -u2 "agent-sandbox: which ends that session and anything it is running (conversations are kept;"
  print -u2 "agent-sandbox: \`claude --continue\` resumes the last one)."
  read -r "reply?agent-sandbox: end the session and $action? [y/N] " || reply=n
  [[ $reply == [yY]* ]] || { print -u2 "agent-sandbox: aborted"; return 1 }
  return 0
}

agent-sandbox-rebuild() {
  emulate -L zsh
  _agent_sandbox_check "$1" || return 1
  local dir=$(_agent_sandbox_dir "$1") name=$(_agent_sandbox_name "$1")
  print "agent-sandbox: rebuilding $name from $dir/.devcontainer — the image runs whatever is in there."
  if docker container inspect "$name" >/dev/null 2>&1; then
    _agent_sandbox_check_workspace "$dir" "$name" || return 1
  fi
  _agent_sandbox_review_gate "$dir" "$name" rebuild || return 1
  _agent_sandbox_confirm_no_live_session "$name" rebuild || return 1
  # --no-cache: otherwise the cached layer keeps the old Claude Code ("latest" at first build)
  _agent_sandbox_build "$dir" --pull --no-cache || return 1
  docker rm -f "$name" >/dev/null 2>&1
  _agent_sandbox_create "$dir" normal || return 1
  print "agent-sandbox: rebuilt $name; run: agent-sandbox${1:+ $1}"
}

agent-sandbox-recreate() {
  emulate -L zsh
  _agent_sandbox_check "$1" || return 1
  local dir=$(_agent_sandbox_dir "$1") name=$(_agent_sandbox_name "$1")
  if ! docker image inspect "$name" >/dev/null 2>&1; then
    print -u2 "agent-sandbox: no image $name yet — run agent-sandbox${1:+ $1}"
    return 1
  fi
  if docker container inspect "$name" >/dev/null 2>&1; then
    _agent_sandbox_check_workspace "$dir" "$name" || return 1
  fi
  # The new container reads CLAUDE_SHORTCUT_FLAGS and agent-sandbox-ports from
  # .devcontainer, which a setup-mode agent could have edited.
  _agent_sandbox_review_gate "$dir" "$name" recreate || return 1
  _agent_sandbox_confirm_no_live_session "$name" recreate || return 1
  docker rm -f "$name" >/dev/null 2>&1
  _agent_sandbox_create "$dir" normal || return 1
  print "agent-sandbox: recreated $name; run: agent-sandbox${1:+ $1}"
}

# The outermost folder at or above $1 that holds a .git directory and a
# .devcontainer directory: the project `agent-sandbox` mounts. Outermost,
# not nearest: a nested repository the agent created can carry both, and a
# check started inside it must still look at the real project. Prints
# nothing when there is none.
_agent_sandbox_project_root() {
  emulate -L zsh
  local d=$(_agent_sandbox_dir "$1") root=""
  while true; do
    [[ -d $d/.git && -d $d/.devcontainer ]] && root=$d
    [[ $d == / ]] && break
    d=${d:h}
  done
  print -r -- "$root"
}

# The host-side checks without Docker and without attaching, for use right
# before git on the host: `agent-sandbox-check && git status`. Returns 1 for
# what `agent-sandbox` refuses on (commondir redirect, unlisted nested
# repository), 0 otherwise; an unfinished rebase is a warning, as at attach.
# Outside a project it checks nothing and returns 0. Runs no git.
agent-sandbox-check() {
  emulate -L zsh
  local quiet=0
  while [[ $1 == -* ]]; do
    case $1 in
      -q|--quiet) quiet=1 ;;
      *) print -u2 "agent-sandbox-check: unknown option $1 (known: -q, --quiet)"; return 2 ;;
    esac
    shift
  done
  local root=$(_agent_sandbox_project_root "$1") bad=0 warned=0
  if [[ -z $root ]]; then
    (( quiet )) || print -u2 "agent-sandbox-check: no project (a folder with .git and .devcontainer) at or above $(_agent_sandbox_dir "$1"); nothing checked"
    return 0
  fi
  _agent_sandbox_check_commondir "$root" || bad=1
  _agent_sandbox_warn_git_in_progress "$root" || warned=1
  if (( quiet )); then
    _agent_sandbox_check_nested_repos "$root" quiet || bad=1
  else
    _agent_sandbox_check_nested_repos "$root" || bad=1
  fi
  if (( bad )); then
    print -u2 "agent-sandbox-check: do not run git in $root on the host until the above is resolved"
    return 1
  fi
  (( quiet || warned )) || print "agent-sandbox-check: $root: no commondir redirect, no unlisted nested repository, no unfinished rebase"
  return 0
}

# Guard against re-running `git init` in an existing repository on the host.
# It changes nothing useful there, but it rewrites .git/config by rename,
# which detaches the container's read-only file mount of it: agent-sandbox
# then refuses to attach until agent-sandbox-recreate. A fresh `git init`
# passes straight through, as does every other git command. Asks only on a
# terminal; scripts and pipes are never stopped. Bypass once with
# `command git init`; turn off with AGENT_SANDBOX_GIT_INIT_GUARD=0 (=always
# asks without a terminal too — the tests use it).
#
# The same wrapper runs `agent-sandbox-check -q` before every git command
# when AGENT_SANDBOX_GIT_CHECK=1 (README "Check before git on the host").
# A git function that is exactly the README's older one-liner
# (`git() { agent-sandbox-check -q || return 1; command git "$@" }`) is
# taken over with the check on; any other git function of yours is left
# alone, and `agent-sandbox --version` says the guard is inactive.
_agent_sandbox_git_init_target() {   # args of a git command line → dir of `init`, or nothing
  emulate -L zsh
  local base=$PWD i=1 dir=""
  local -a a=("$@")
  while (( i <= $#a )); do
    case ${a[i]} in
      -C) [[ ${a[i+1]} == /* ]] && base=${a[i+1]} || base=$base/${a[i+1]}; (( i += 2 )) ;;
      -c|--git-dir|--work-tree|--namespace|--exec-path|--config-env) (( i += 2 )) ;;
      -*) (( i++ )) ;;
      init) break ;;
      *) return 0 ;;   # some other subcommand
    esac
  done
  (( i <= $#a )) || return 0
  for (( i++; i <= $#a; i++ )); do
    case ${a[i]} in
      --bare) return 0 ;;   # a bare repository has no .git to look at
      --template|--separate-git-dir|-b|--initial-branch|--object-format|--ref-format) (( i++ )) ;;
      -*) ;;
      *) dir=${a[i]}; break ;;
    esac
  done
  [[ -z $dir ]] && dir=$base || { [[ $dir == /* ]] || dir=$base/$dir }
  print -r -- ${dir:A}
}

if (( $+functions[git] )) && [[ $functions[git] != *AGENT_SANDBOX_GIT_INIT_GUARD* ]] &&
   [[ ${${functions[git]//[[:space:]]/}} == 'agent-sandbox-check-q||return1commandgit"$@"' ]]; then
  _agent_sandbox_git_check_default() { return 0 }   # README one-liner taken over: check on
  unfunction git
fi
if (( ! $+functions[git] )) || [[ $functions[git] == *AGENT_SANDBOX_GIT_INIT_GUARD* ]]; then
  git() {
    emulate -L zsh
    local guard=${AGENT_SANDBOX_GIT_INIT_GUARD:-1} dir reply
    if [[ ${AGENT_SANDBOX_GIT_CHECK:-} == 1 ]] ||
       { [[ -z ${AGENT_SANDBOX_GIT_CHECK:-} ]] && (( $+functions[_agent_sandbox_git_check_default] )) }; then
      agent-sandbox-check -q || return 1
    fi
    if [[ $guard == always || ( $guard != 0 && -t 0 ) ]]; then
      dir=$(_agent_sandbox_git_init_target "$@")
      if [[ -n $dir && -e $dir/.git ]]; then
        print -u2 "agent-sandbox: $dir already has a .git — reinitializing it could break agent-sandbox."
        print -u2 "agent-sandbox: git init rewrites .git/config, which detaches the container's read-only mount of it;"
        print -u2 "agent-sandbox: agent-sandbox then refuses to attach until agent-sandbox-recreate (ending any running session)."
        read -r "reply?agent-sandbox: reinitialize it anyway? [y/N] " || reply=n
        [[ $reply == [yY]* ]] || { print -u2 "agent-sandbox: git init skipped"; return 1 }
      fi
    fi
    command git "$@"   # the user's own command, passed through unchanged
  }
fi

agent-sandbox-stop()  { emulate -L zsh; docker stop "$(_agent_sandbox_name "$1")" >/dev/null }
agent-sandbox-ports() { emulate -L zsh; docker port "$(_agent_sandbox_name "$1")" }
