# Claude Code shell shortcuts for the dev container. Baked into the image at
# /etc/zsh/claude-harness.zsh and sourced at the end of ~/.zshrc (see the
# Dockerfile), so edits here need a rebuild. Harness file, mirrored by
# scripts/sync-harness.sh — put personal aliases in ~/.zshrc instead.
#
# CLAUDE_SHORTCUT_FLAGS — extra flags every shortcut passes to `claude`. Set
# it per project in devcontainer.json ("containerEnv"), typically to the flag
# that skips permission prompts: inside this container the sandbox is the
# permission system (default-deny firewall, only /workspace mounted, no host
# access), so per-tool prompts add friction without adding safety. Leave it
# empty for a project where you want the prompts. Plain `claude` never gets
# the flags either way, and none of this exists on the host.

alias cc='claude ${=CLAUDE_SHORTCUT_FLAGS}'
alias ccc='claude --continue ${=CLAUDE_SHORTCUT_FLAGS}'
alias ccr='claude --resume ${=CLAUDE_SHORTCUT_FLAGS}'

# ccw <name> [base-ref] [-- claude args...]
# Session in a git worktree at .claude/worktrees/<name> on branch
# worktree-<name>. Creates it from <base-ref> if it doesn't exist — prompted
# when omitted (default branch / dev / develop / current) — then hands it to
# `claude --worktree`, which reuses an existing worktree of that name and
# keeps its exit-time cleanup. `ccw <name>` later just reopens it.
ccw() {
  local name="$1" base=""
  [[ -n "$name" ]] || { echo "usage: ccw <name> [base-ref] [-- claude args...]" >&2; return 1; }
  shift
  if [[ -n "$1" && "$1" != "--" ]]; then base="$1"; shift; fi
  [[ "$1" == "--" ]] && shift
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ccw: not in a git repo" >&2; return 1; }
  local dir="$root/.claude/worktrees/$name"
  if [[ ! -d "$dir" ]]; then
    if [[ -z "$base" ]]; then
      local def cur b i choice; local -a opts
      def=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); def=${def#origin/}
      [[ -n "$def" ]] || { git show-ref -q --verify refs/heads/main && def=main || def=master; }
      cur=$(git branch --show-current)
      opts=("$def")
      for b in dev develop; do
        [[ "$b" != "$def" ]] && git show-ref -q --verify "refs/heads/$b" && opts+=("$b")
      done
      [[ -n "$cur" && "$cur" != "$def" ]] && (( ! ${opts[(Ie)$cur]} )) && opts+=("$cur")
      echo "Base for new worktree '$name':"
      i=1
      for b in "${opts[@]}"; do
        printf '  [%d] %s%s\n' "$i" "$b" "$([[ "$b" == "$cur" ]] && echo ' (current)')"; ((i++))
      done
      read "choice?Number, or any ref [1]: "
      if [[ -z "$choice" ]]; then base="${opts[1]}"
      elif [[ "$choice" == <-> && $choice -ge 1 && $choice -le ${#opts} ]]; then base="${opts[$choice]}"
      else base="$choice"; fi
    fi
    git rev-parse -q --verify "${base}^{commit}" >/dev/null || { echo "ccw: unknown ref '$base'" >&2; return 1; }
    git worktree add "$dir" -b "worktree-$name" "$base" || return 1
    echo "Created $dir on branch worktree-$name from $base"
  fi
  claude --worktree "$name" ${=CLAUDE_SHORTCUT_FLAGS} "$@"
}

# cc-update [version]
# Reinstall Claude Code inside this container — the one supported way to
# update it between rebuilds. `claude update` and a bare `npm install -g`
# both break here: the repo's .npmrc sets ignore-scripts=true, which npm
# applies even to -g installs run from /workspace, so the wrapper updates but
# the platform-native binary is never linked and the next `claude` dies with
# "native binary not installed" (then ENOTEMPTY on reinstall). This passes
# the same flags the Dockerfile's install uses, runs from $HOME so no project
# .npmrc applies, retries once after clearing a half-installed package, and
# verifies with `claude --version`. Lasts until the next rebuild, which
# installs CLAUDE_CODE_VERSION from devcontainer.json (default: latest).
cc-update() {
  local ver="${1:-latest}" pkg='@anthropic-ai/claude-code' prefix before after
  if [[ -n "$CLAUDECODE" ]]; then
    echo "cc-update: run from a plain terminal, not inside a Claude session" >&2
    return 1
  fi
  prefix="$(npm prefix -g)" || return 1
  before="$(claude --version 2>/dev/null)" || before="(broken install)"
  echo "cc-update: $before -> $pkg@$ver"
  _cc_npm_install() {
    ( cd "$HOME" && npm install -g "$pkg@$ver" \
        --include=optional --allow-scripts="$pkg" --ignore-scripts=false )
  }
  if ! _cc_npm_install; then
    echo "cc-update: install failed; clearing the package and retrying once" >&2
    rm -rf "$prefix/lib/node_modules/@anthropic-ai/claude-code" \
           "$prefix/lib/node_modules/@anthropic-ai/.claude-code-"*(N)
    _cc_npm_install || { echo "cc-update: still failing — rebuild the container" >&2; return 1; }
  fi
  if ! after="$(claude --version 2>&1)"; then
    echo "cc-update: installed but \`claude --version\` fails: $after" >&2
    return 1
  fi
  echo "cc-update: now $after"
  echo "cc-update: a container rebuild reinstalls CLAUDE_CODE_VERSION from devcontainer.json (default latest, i.e. this version or newer)"
}

cc-help() {
  local f="${CLAUDE_SHORTCUT_FLAGS:-(none — set CLAUDE_SHORTCUT_FLAGS in devcontainer.json containerEnv)}"
  cat <<HELP
Claude Code shortcuts (this container only):
  cc                  claude                      new session
  ccc                 claude --continue           resume the last session here
  ccr                 claude --resume             pick a session to resume
  ccw <name> [base]   claude --worktree <name>    session in a fresh worktree
                      (base prompted if omitted; \`ccw <name>\` later reopens it)
  cc-update [ver]     reinstall Claude Code         update between rebuilds
                      (the only way that works here; \`claude update\` is blocked)
  cc-help             this list
Extra flags the session shortcuts pass (CLAUDE_SHORTCUT_FLAGS): $f
Full commands are in shell history too: Ctrl-R "claude". Plain \`claude\` keeps prompts.
Firewall re-run: sudo /usr/local/bin/init-firewall.sh
HELP
}

# Seed the full commands into the persisted history once per history file, so
# Ctrl-R / up-arrow find them on a fresh volume. Idempotent (each line only if
# absent); the stamp file records the flags they were seeded with, so later
# shells skip the check until CLAUDE_SHORTCUT_FLAGS changes. Interactive only.
# No locking: several terminals opened at the same instant on a fresh volume
# can each seed — a cosmetic duplicate in Ctrl-R, accepted.
if [[ -o interactive && -n "$HISTFILE" ]]; then
  _cc_stamp="${HISTFILE}.harness-seeded"
  if [[ ! -e "$_cc_stamp" || "$(<"$_cc_stamp")" != "$CLAUDE_SHORTCUT_FLAGS" ]]; then
    _cc_sfx="${CLAUDE_SHORTCUT_FLAGS:+ $CLAUDE_SHORTCUT_FLAGS}"
    _cc_cmds=(
      "claude$_cc_sfx"
      "claude --continue$_cc_sfx"
      "claude --resume$_cc_sfx"
      "claude -w my-feature$_cc_sfx"
      'sudo /usr/local/bin/init-firewall.sh'
    )
    touch "$HISTFILE" 2>/dev/null
    if [[ -w "$HISTFILE" ]]; then
      _cc_now=$(date +%s)
      for _cc_cmd in "${_cc_cmds[@]}"; do
        # Exact whole-command match, with the EXTENDED_HISTORY ": ts:0;" prefix
        # stripped — a substring test would take "claude --x" as already
        # present when only "claude --x --y" is, and never seed the shorter one.
        sed 's/^: [0-9]*:[0-9]*;//' "$HISTFILE" 2>/dev/null | grep -qxF -- "$_cc_cmd" \
          || printf ': %s:0;%s\n' "$_cc_now" "$_cc_cmd" >> "$HISTFILE"
      done
      fc -R "$HISTFILE" 2>/dev/null
      print -r -- "$CLAUDE_SHORTCUT_FLAGS" > "$_cc_stamp"
      echo "Claude Code shortcuts: cc, ccc, ccr, ccw <name> — \`cc-help\` for details."
    fi
    unset _cc_cmds _cc_cmd _cc_now _cc_sfx
  fi
  unset _cc_stamp
fi
