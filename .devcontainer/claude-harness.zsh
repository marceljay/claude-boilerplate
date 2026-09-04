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

cc-help() {
  local f="${CLAUDE_SHORTCUT_FLAGS:-(none — set CLAUDE_SHORTCUT_FLAGS in devcontainer.json containerEnv)}"
  cat <<HELP
Claude Code shortcuts (this container only):
  cc                  claude                      new session
  ccc                 claude --continue           resume the last session here
  ccr                 claude --resume             pick a session to resume
  ccw <name> [base]   claude --worktree <name>    session in a fresh worktree
                      (base prompted if omitted; \`ccw <name>\` later reopens it)
  cc-help             this list
Extra flags all of them pass (CLAUDE_SHORTCUT_FLAGS): $f
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
