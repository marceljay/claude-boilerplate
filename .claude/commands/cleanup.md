# Code Cleanup

Run lint, format, and remove unused imports across changed files.

## Steps

1. Identify changed files:
   - `git diff --name-only` for unstaged changes
   - `git diff --cached --name-only` for staged changes
   - If nothing is changed, run against all source files

2. Detect the stack from the files present, then run that ecosystem's
   lint → format → type-check tools in order. Only run tools that are actually
   installed/configured. Common mappings:
   - **Node/TS** (`package.json`): `npm run lint -- --fix` (or eslint/biome),
     `npx prettier --write`, remove unused imports, `npx tsc --noEmit`
   - **Python** (`pyproject.toml`/`requirements.txt`): `ruff check --fix`,
     `ruff format` (or `black`), `mypy` if configured
   - **Rust** (`Cargo.toml`): `cargo clippy --fix`, `cargo fmt`
   - **Go** (`go.mod`): `gofmt -w`, `go vet`
   - **Any** (`Makefile` with a `lint`/`fmt` target): prefer `make lint` / `make fmt`
   - If you can't tell the stack, ask the user rather than guessing.

3. Show a summary of what was fixed:
   - Files modified
   - Number of lint errors fixed
   - Number of unused imports removed
   - Any remaining errors that need manual attention

4. Do NOT commit automatically. Let the user decide when to commit.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*