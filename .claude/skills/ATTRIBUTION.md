# Vendored Skills — Attribution

The following skills are vendored (copied) from the **Superpowers** collection by
Jesse Vincent, so they ship with this boilerplate out of the box:

- `using-superpowers/` — how to find and invoke skills (the "Superpowers" meta-skill)
- `test-driven-development/` — red-green-refactor discipline (TDD)
- `systematic-debugging/` — root-cause-first debugging
- `writing-plans/` — turn a spec into a bite-sized implementation plan
- `brainstorming/` — turn an idea into a design/spec via dialogue

## Local modifications

These vendored copies differ from upstream (changes © the boilerplate, same MIT):

- **`writing-plans` and `brainstorming` are "ask-first."** Upstream auto-fires
  brainstorming before any creative work and hard-gates all implementation until a
  design is approved. Here both skills instead **ask the user whether to start**
  and only gate once the user opts in — so a boilerplate user isn't forced into a
  design interview for every small change.
- **Output paths point at `_planning/`** (`_planning/plans/`, `_planning/specs/`)
  instead of upstream's `docs/superpowers/…`, matching this repo's state-file layout.
- **The `brainstorming` "visual companion"** (a browser/localhost-server feature) is
  not vendored — this boilerplate's dev container has no host browser.
- **`test-driven-development` is policy-gated.** Upstream fires on any feature or
  bugfix; here it fires only when the project CLAUDE.md records
  `Testing policy: tdd` or the user explicitly asks for tests-first. Testing is a
  per-project choice (`on-request | tests-with-features | tdd`), asked once and
  recorded — like the commit policy.
- **`using-superpowers` is toned down.** Upstream mandates invoking any skill with
  "even a 1% chance" of relevance before any response, and pushes brainstorming
  before plan mode. Here it says: invoke a *clearly relevant* skill before starting,
  announce it, user instructions always win, and respect policy gates. The red-flags
  table and mandatory-dispatch flowchart are dropped.

Source: https://github.com/obra/superpowers (skills under `skills/`).
Only the Claude Code platform reference is vendored from `using-superpowers`;
upstream also ships Codex/Copilot/Gemini/Pi/Antigravity references and many more
skills. To get the full, unmodified, auto-updating set instead, install the plugin:

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

## License

These files are distributed under the MIT License:

```
MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
