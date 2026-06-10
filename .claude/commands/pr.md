# Create Pull Request

Create a pull request with a standardized format.

## Steps

1. Gather context:
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

## Test Plan
<how to verify these changes work>
```

3. Create the PR:
   ```
   gh pr create --title "..." --body "..."
   ```

4. Return the PR URL to the user.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*