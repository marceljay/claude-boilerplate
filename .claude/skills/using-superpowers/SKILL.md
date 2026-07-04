---
name: using-superpowers
description: Use when starting a conversation — how to find and invoke the bundled skills; user instructions always take precedence
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this skill.
</SUBAGENT-STOP>

# Using Skills

When a skill clearly applies to the task at hand, invoke it **before** starting
the work, and announce it: "Using [skill] to [purpose]". If an invoked skill
turns out to be wrong for the situation, say so and set it aside — don't force
it. (Toned down from upstream, which mandated invocation at a "1% chance of
relevance" — see ATTRIBUTION.md.)

## Instruction Priority

1. **User's explicit instructions** (CLAUDE.md, AGENTS.md, direct requests) — highest
2. **Skills** — override default system behavior where they conflict
3. **Default system prompt** — lowest

If CLAUDE.md and a skill disagree, CLAUDE.md wins. Some bundled skills are
gated on a recorded per-project policy (e.g. `test-driven-development` fires
only under `Testing policy: tdd`) — respect the gate; don't reach for a rigid
skill the project hasn't opted into.

## Mechanics

- Load skills through the platform's skill mechanism (in Claude Code, the
  `Skill` tool), never by reading the SKILL.md files with file tools —
  invocation is what activates them.
- **Rigid** skills (test-driven-development, systematic-debugging) are followed
  exactly once active; **flexible** skills adapt principles to context. The
  skill itself says which.
- When a skill has a checklist, create a todo per item before executing.
- Skills speak in platform-neutral actions ("dispatch a subagent", "create a
  todo"); the Claude Code tool mapping is in
  [references/claude-code-tools.md](references/claude-code-tools.md).
