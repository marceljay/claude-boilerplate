# Remember Global Preference

Save a preference or behavior based on the user's natural language description.

## Usage

`/remember <description of desired behavior>`

## Step 0 — pick the right scope for this environment

**In a dev container** (`/.dockerenv` exists, or `$REMOTE_CONTAINERS`/
`$DEVCONTAINER` is set) `~/.claude/` is **not** the user's real global config — it's
a per-container Docker volume (`claude-code-config-${devcontainerId}`). Anything
written there applies only inside this one container and is **lost if the volume is
rebuilt**, and it doesn't carry to the user's other projects. So "global" is
effectively meaningless here. Persist to the bind-mounted `/workspace` instead,
which lives on the host and is version-controlled — **unless** `/init`'s
"keep the harness local" option put `.claude/` in `.gitignore`. The project
CLAUDE.md records which as a `- Harness: committed | local` line (fall back to
`git check-ignore -q .claude/CLAUDE.md` if the line is missing). With
`Harness: local`, every target in the dev-container column is local to this
machine, the "shared/committed" branch below does not exist, and you must say
so rather than promise sharing.

| What                  | Dev-container target                                                                                                       | Host target (no container) |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| Tool permission       | `.claude/settings.local.json` (per-dev, gitignored) — or `.claude/settings.json` if the user wants it **shared/committed** | `~/.claude/settings.json`  |
| Behavioral preference | project `.claude/CLAUDE.md`                                                                                                | `~/.claude/CLAUDE.md`      |
| Project fact (memory) | config-dir `memory/` + run `/backup-memory`                                                                                | config-dir `memory/`       |

Detect once at the start and use the matching column for the rest of the steps.

## Steps

1. Parse the user's description and classify it:

   **Tool permission** (`permissions.allow`):
   - "allow rm commands" -> add `Bash(rm:*)`
   - "allow docker" -> add `Bash(docker:*)`
   - "let me use bun" -> add `Bash(bun:*)`
   - Any request to auto-approve a specific command or tool
   - In a container, default to `.claude/settings.local.json` (personal, already
     gitignored). Only use the committed `.claude/settings.json` if the user says
     the permission should be shared with the team.

   **Behavioral instruction** (a CLAUDE.md):
   - "always run tests after changes"
   - "prefer bun over npm"
   - "don't auto-commit"
   - "use tabs not spaces"
   - Any preference about how Claude should work, communicate, or make decisions
   - In a container this lands in the project `.claude/CLAUDE.md`, so it's shared
     with everyone who clones the repo. If the user wants it personal-only, say so —
     there's no per-developer CLAUDE.md, so the honest options are to keep it in
     `settings.local.json` (if expressible as a permission) or accept it's shared.

   **Project memory** (config-dir memory for this project —
   `$CLAUDE_CONFIG_DIR/projects/<repo-slug>/memory/`, _not_ a folder in the repo;
   one fact per file plus a `MEMORY.md` index entry):
   - "this project uses port 4000"
   - "the API is at /v2 not /v1"
   - Any fact specific to the current project, not global
   - This also lives on the container volume, so run `/backup-memory` afterward to
     mirror it into the repo against volume loss.

2. Show the user:
   - What will be saved
   - Where it will be saved (the resolved path for this environment)
   - The exact content being added

3. Save it to the resolved target:
   - **settings (local or shared)**: add to the `permissions.allow` array
   - **CLAUDE.md**: append under the most relevant existing section, or create a
     new `## User Preferences` section if none fits
   - **Project memory**: write the fact as one file in the config-dir `memory/`
     directory, add a one-line pointer to its `MEMORY.md` index, then run
     `/backup-memory`

4. Confirm what was saved and where, and note its true scope — e.g. "Saved to
   `.claude/settings.local.json` (this project, this developer)" rather than
   implying it's global, since in a container it isn't.

## Classification Priority

If unclear, default to a CLAUDE.md (project `.claude/CLAUDE.md` in a container).
Behavioral instructions are the most common case.

---
