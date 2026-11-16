- **Two more host-executed git files are out of the agent's reach.** A
  registered submodule's `.git/modules/<name>/config` (read by the host's
  `git status`) is now mounted read-only per file, and `agent` refuses to
  attach when a linked worktree's `.git/worktrees/<name>/commondir` holds
  anything but `../..` (git run inside that worktree on the host would
  follow it). `agent` also reminds you to set `diff.ignoreSubmodules all`
  on the host whenever nested repositories are listed; that setting was
  verified to keep status, diff, log, fetch, grep, ls-files, stash,
  checkout, add, commit, push, gc and fsck out of nested repositories.
  The `.git/commondir` placeholder check now requires exactly one byte, so
  a trailing newline is refused instead of being read as `.`.
