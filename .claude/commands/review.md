---
description: Build (and optionally serve) the click-through review page for items in "Needs input" / _planning/REVIEW.md, then record the decisions the user pastes back.
---

# Review Page

Render everything waiting on the user's decision as a page they can click
through — one card per item with Approve / Needs change / Reject / Skip and a
notes box — instead of a wall of questions in chat.

1. Run `python3 .claude/scripts/review_page.py` (add `--serve [PORT]` if the
   user wants it served from the container; then print the URL and remind
   them the editor forwards to a host port that may differ). It reads
   `_planning/REVIEW.md` if present, else the `## Needs input` section of
   STATUS.md, and writes `_planning/review.html` (gitignored). Print the
   path — the workspace is bind-mounted, so the user opens it from the host.
   Never try to open a browser yourself.

2. When the user pastes back a `## Review decisions (…)` block: apply each
   decision (approve → the item leaves Needs input and work continues or
   lands in CHANGELOG; needs change → back to In Progress with the note;
   reject → gone, note in CHANGELOG if it undoes shipped work; skip → stays),
   through the `update-status` skill in one edit. Bump the date.

This command works regardless of the `Review page:` line in CLAUDE.md. That
line only controls whether the `update-status` skill regenerates the page on
its own each time Needs input changes (`on`), or leaves it to `/review`
(`off`, the default — the generator is cheap, but re-running it on every
status edit is still a tool call per edit).
