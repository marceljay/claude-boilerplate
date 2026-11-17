- **`agent-sandbox-check [-q] [dir]`: the host-side checks without Docker
  and without attaching.** `agent-sandbox` looks for a `.git/commondir`
  redirect, unlisted nested repositories and an unfinished rebase only
  when it starts; the agent can create the last two afterwards. The new
  command runs the same checks on their own, from any subfolder of the
  project, so they can directly precede git on the host
  (`agent-sandbox-check && git status`). Exit 1 for what `agent-sandbox`
  refuses on, a warning for an unfinished rebase, nothing checked outside
  a project. The README shows an optional zsh function that runs it before
  every `git` typed in that shell; editors and git-aware prompts are not
  covered. The bash shim from `sync-harness.sh --install-shell` gains the
  command.
