- Git worktrees get the harness even when `.claude/` is gitignored: a root
  `.worktreeinclude` allowlists CLAUDE.md, settings.json, hooks, skills,
  commands, agents and scripts for Claude Code to copy into every worktree
  it creates. Before, a `Harness: local` project's worktrees ran with no
  instructions, hooks, status line, or permissions. Explicit list rather than
  `.claude/`, which would also copy nested worktrees and logs (negation
  patterns are ignored). `sync-harness.sh` carries it as an ask-first file.
