- **`agent-sandbox` warns about an unfinished rebase, and the drift warning no
  longer tells you to run git on the host.** A third external review
  (2026-11-16) showed that a container can leave an interactive rebase
  stopped before an `exec` line; `git rebase --continue` on the host then
  runs it. `agent-sandbox`, the review gate and `.devcontainer/initialize.sh`
  now warn (without blocking, without running git) when `.git/rebase-merge`,
  `.git/rebase-apply` or `.git/sequencer` exists, also under
  `.git/worktrees/*/`. The drift warning, the script header, the README and
  `/init` point at `agent-sandbox-rebuild`, which shows the `.devcontainer`
  diff without git, instead of `git diff -- .devcontainer`.
  `docs/SECURITY-MODEL.md` scenario 3 documents the rebase case with the
  rule "abort a rebase you did not start, never continue it", records as an
  accepted residual risk that nested repositories and rebases are detected
  only at attach and in the gate, and corrects the `diff.ignoreSubmodules`
  note: `git add .`/`-A`/`-u` and a `.gitmodules` entry with `ignore = none`
  are not covered by it. The script's messages no
  longer present that setting as a remedy.
