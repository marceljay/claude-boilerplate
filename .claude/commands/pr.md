# Create Pull Request

Create a pull request with a standardized format.

## Steps

1. Gather context:
   - Whether a PR can be opened from here: `gh` on PATH **and** `gh auth
     status` succeeds **and** `git remote get-url origin` is a GitHub URL. If
     any of those fails, use the file fallback in step 3b — don't try to
     install `gh` or guess at another host's CLI.
   - Current branch name and base branch
   - All commits since diverging from base (`git log base..HEAD --oneline`)
   - Full diff summary (`git diff base...HEAD --stat`)
   - Check if branch is pushed to remote; push with `-u` if not

2. Draft the PR:
   - **Title**: Derive from branch name or commits. Use conventional format: `feat: ...`, `fix: ...`, etc. Under 70 characters.
   - **Body**: Use this template:

```markdown
## Summary

<1-3 bullet points describing what this PR does>

## Changes

<bulleted list of specific changes, grouped by area>

## Commits

<one bullet per commit on the branch, oldest first, in the form
`<short sha> <commit title>` — taken verbatim from
`git log base..HEAD --reverse --format='- %h %s'`, never paraphrased>

## Test Plan

<how to verify these changes work>
```

3. Create the PR:

   ```
   gh pr create --title "..." --body "..."
   ```

   Return the PR URL to the user.

   The Commits section is mandatory in both paths: it is what lets a
   reviewer map the description to the history without opening the branch.

3b. **No `gh`, not authenticated, or not a GitHub remote:** write the
   description to `.temp/pr-<branch>.md` (gitignored; `<branch>` with `/`
   replaced by `-`), title as the first line, then the body from step 2, and
   push the branch. Tell the user the file path and the compare URL if the
   remote's host has an obvious one (GitHub/GitLab/Bitbucket
   `…/compare/<base>...<branch>`); they open the PR in the browser and paste.
   Never print the whole description into the chat as well — the file is the
   deliverable.

---
