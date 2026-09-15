- **50/72 commit messages are enforced by a hook.** `CLAUDE.md` states the
  rule as hard (title ≤50, blank line, body wrapped at 72) and the new
  `.claude/hooks/commit_msg_check.py` PreToolUse hook rejects a `git commit`
  whose `-m` or heredoc message breaks it. Lines carrying a URL are exempt
  from the 72 limit; editor and on-disk `-F` messages aren't judged.
