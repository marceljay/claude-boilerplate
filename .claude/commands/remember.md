# Remember Global Preference

Save a global preference or behavior based on the user's natural language description.

## Usage
`/remember <description of desired behavior>`

## Steps

1. Parse the user's description and classify it:

   **Tool permission** (goes in `~/.claude/settings.json` under `permissions.allow`):
   - "allow rm commands" -> add `Bash(rm:*)`
   - "allow docker" -> add `Bash(docker:*)`
   - "let me use bun" -> add `Bash(bun:*)`
   - Any request to auto-approve a specific command or tool

   **Behavioral instruction** (goes in `~/.claude/CLAUDE.md`):
   - "always run tests after changes"
   - "prefer bun over npm"
   - "don't auto-commit"
   - "use tabs not spaces"
   - Any preference about how Claude should work, communicate, or make decisions

   **Project memory** (goes in the current project's `memory/MEMORY.md`):
   - "this project uses port 4000"
   - "the API is at /v2 not /v1"
   - Any fact specific to the current project, not global

2. Show the user:
   - What will be saved
   - Where it will be saved (file path)
   - The exact content being added

3. Save it to the appropriate file:
   - **settings.json**: Add to the `permissions.allow` array
   - **CLAUDE.md**: Append under the most relevant existing section, or create a new `## User Preferences` section if none fits
   - **memory/MEMORY.md**: Append under a relevant heading or create one

4. Confirm: "Saved to [file]. This will persist across all future sessions."

## Classification Priority
If unclear, default to `~/.claude/CLAUDE.md`. Behavioral instructions are the most common case.

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*