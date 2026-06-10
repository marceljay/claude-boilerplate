# Code Cleanup

Run lint, format, and remove unused imports across changed files.

## Steps

1. Identify changed files:
   - `git diff --name-only` for unstaged changes
   - `git diff --cached --name-only` for staged changes
   - If nothing is changed, run against all source files

2. Run available tools in order:
   - **Linter**: `npm run lint -- --fix` (or eslint, biome, etc.)
   - **Formatter**: `npx prettier --write` on changed files (if prettier is installed)
   - **Unused imports**: Check for and remove unused imports in changed TypeScript/JavaScript files
   - **Type check**: `npx tsc --noEmit` to verify no type errors

3. Show a summary of what was fixed:
   - Files modified
   - Number of lint errors fixed
   - Number of unused imports removed
   - Any remaining errors that need manual attention

4. Do NOT commit automatically. Let the user decide when to commit.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*