#!/usr/bin/env python3
"""Fold changelog fragments into CHANGELOG.md.

Why fragments: with several agents on separate branches or worktrees, every
one of them inserting at the top of `## [Unreleased]` is a guaranteed merge
conflict at the same spot. So a branch never edits CHANGELOG.md. It adds one
file per change under `changelog.d/`:

    changelog.d/<slug>.<added|changed|fixed|removed>.md

whose content is the entry's bullet text (markdown; a leading "- " is added if
missing). Distinct files never conflict. Folding happens on the release
branch, sequentially, by this script:

    changelog_fold.py                 # fragments -> "## [Unreleased]"
    changelog_fold.py --version 1.4.0 # fragments + Unreleased -> "## [1.4.0] - <today>"
    changelog_fold.py --check         # list pending fragments, exit 1 if any

Fragments are grouped by type in the order Added, Changed, Fixed, Removed,
inserted at the top of the matching "### <Type>" subsection (created if
absent), and deleted. Files in changelog.d/ that don't match the pattern
(README.md, .gitkeep) are ignored. Exit 0 when there is nothing to do.
"""

import os
import re
import sys
from datetime import date

ROOT = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
FRAG_DIR = os.path.join(ROOT, "changelog.d")
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
TYPES = ["added", "changed", "fixed", "removed"]
FRAG_RE = re.compile(r"^(?P<slug>.+)\.(?P<type>added|changed|fixed|removed)\.md$")


def load_fragments():
    if not os.path.isdir(FRAG_DIR):
        return {}
    by_type = {t: [] for t in TYPES}
    for name in sorted(os.listdir(FRAG_DIR)):
        m = FRAG_RE.match(name)
        if not m:
            continue
        with open(os.path.join(FRAG_DIR, name), encoding="utf-8") as f:
            body = f.read().strip()
        if not body:
            continue
        if not body.startswith("- "):
            body = "- " + body
        by_type[m.group("type")].append((name, body))
    return {t: v for t, v in by_type.items() if v}


def split_unreleased(text):
    """Return (head, unreleased_body, tail) around the `## [Unreleased]` section."""
    m = re.search(r"^## \[Unreleased\][^\n]*\n", text, re.M)
    if not m:
        raise SystemExit("CHANGELOG.md has no '## [Unreleased]' heading")
    start = m.end()
    nxt = re.search(r"^## ", text[start:], re.M)
    end = start + nxt.start() if nxt else len(text)
    return text[: m.start()], text[m.start():start], text[start:end], text[end:]


def merge_into_section(body, frags):
    """Insert fragment bullets at the top of each `### Type` subsection."""
    for t in TYPES:
        if t not in frags:
            continue
        bullets = "\n".join(b for _, b in frags[t]) + "\n"
        heading = f"### {t.capitalize()}"
        m = re.search(rf"^{re.escape(heading)}[ \t]*\n\n?", body, re.M)
        if m:
            body = body[: m.end()] + bullets + body[m.end():]
        else:
            body = body.rstrip("\n") + f"\n\n{heading}\n\n{bullets}"
    return body.rstrip("\n") + "\n\n"


def main(argv):
    frags = load_fragments()
    if "--check" in argv:
        n = sum(len(v) for v in frags.values())
        for t in TYPES:
            for name, _ in frags.get(t, []):
                print(name)
        return 1 if n else 0

    version = None
    if "--version" in argv:
        i = argv.index("--version")
        if i + 1 >= len(argv):
            raise SystemExit("--version needs a value")
        version = argv[i + 1]

    if not os.path.exists(CHANGELOG):
        raise SystemExit("no CHANGELOG.md here")
    with open(CHANGELOG, encoding="utf-8") as f:
        text = f.read()
    head, heading, body, tail = split_unreleased(text)

    if not frags and not version:
        print("nothing to fold")
        return 0
    if version and not frags and not body.strip():
        raise SystemExit("[Unreleased] is empty and there are no fragments — nothing to release")

    body = merge_into_section(body, frags) if frags else body
    if version:
        released = f"## [{version}] - {date.today().isoformat()}\n" + body
        text = head + "## [Unreleased]\n\n" + released + tail
    else:
        text = head + heading + body + tail

    with open(CHANGELOG, "w", encoding="utf-8") as f:
        f.write(text)
    removed = []
    for t in TYPES:
        for name, _ in frags.get(t, []):
            os.remove(os.path.join(FRAG_DIR, name))
            removed.append(name)
    where = f"[{version}]" if version else "[Unreleased]"
    print(f"folded {len(removed)} fragment(s) into CHANGELOG.md {where}: " + ", ".join(removed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
