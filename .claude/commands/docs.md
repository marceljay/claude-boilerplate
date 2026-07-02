# Update Documentation

Manually trigger documentation updates to match current code state.

## Steps

0. Try to execute `docs-updater` subagent.
1. Scan recent git changes to understand what has changed:
   - `git log --oneline -10` for recent commits
   - `git diff HEAD~5 --stat` for files changed

2. Identify documentation that needs updating:
   - **README.md** — project overview, setup instructions, features list, API docs
   - **User-facing docs** — Docusaurus/docs folder if it exists
   - **CHANGELOG.md** — any unreleased changes not yet logged

3. Delegate updates to a background subagent using the Task tool with `run_in_background: true`:
   - The subagent reads the changed code and updates all relevant docs
   - Updates should reflect what end users need to know, not implementation details
   - If README.md doesn't exist, create one with: project name, description, setup/install, usage, tech stack, and license

4. The subagent should commit doc changes separately:
   - `docs: update README for [feature/change]`
   - `docs: update user docs for [feature/change]`

5. Report back to the user what was updated.
