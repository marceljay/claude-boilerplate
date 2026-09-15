#!/usr/bin/env python3
"""PreToolUse (Bash) hook: enforce the 50/72 commit-message rule.

Finds `git commit` in the command and checks the message it would create:
  - title (first line) at most 50 characters
  - a blank line between title and body
  - every body line at most 72 characters (lines carrying a URL are exempt —
    they cannot be wrapped)

The message is read from `-m`/`--message` arguments (each one is a paragraph,
as git joins them) or from a heredoc fed to `-F -` / `--file=-`. Messages git
would open in an editor, or read from a file on disk, are not judged here.
Blocks with exit 2 and a reason; fails open on its own bugs (logged to
.claude/logs/hook_errors.log) so a hook error never stops every Bash call.
"""
import json
import os
import re
import shlex
import sys

WS = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
TITLE_MAX, BODY_MAX = 50, 72
HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def deny(reason):
    print(
        f"BLOCKED by .claude/hooks/commit_msg_check.py: {reason}. "
        f"Commit messages follow 50/72: title ≤{TITLE_MAX} chars, blank line, "
        f"body wrapped at {BODY_MAX}. Rewrite the message and commit again.",
        file=sys.stderr,
    )
    sys.exit(2)


def first_heredoc_body(cmd):
    """Body of the first heredoc in the command, or None."""
    lines = cmd.split("\n")
    for i, line in enumerate(lines):
        m = HEREDOC_RE.search(line)
        if m:
            tag, body = m.group(2), []
            for l in lines[i + 1:]:
                if l.strip() == tag:
                    break
                body.append(l)
            return "\n".join(body)
    return None


def messages_from_args(cmd):
    """Return the commit message from -m/--message args, or from a heredoc
    when the command uses -F - / --file=-. None when neither applies."""
    # Tokenise without heredoc bodies (they're data to the shell), keep a copy.
    stripped = "\n".join(HEREDOC_RE.sub("", l) for l in cmd.split("\n"))
    try:
        toks = shlex.split(stripped, posix=True)
    except ValueError:
        return None
    if "git" not in toks or "commit" not in toks:
        return None
    parts, stdin_file, i = [], False, 0
    while i < len(toks):
        t = toks[i]
        if t in ("-m", "--message") and i + 1 < len(toks):
            parts.append(toks[i + 1]); i += 2; continue
        if t.startswith("-m") and len(t) > 2 and not t.startswith("--"):
            parts.append(t[2:]); i += 1; continue
        if t.startswith("--message="):
            parts.append(t.split("=", 1)[1]); i += 1; continue
        if t in ("-F", "--file") and i + 1 < len(toks):
            stdin_file = toks[i + 1] == "-"; i += 2; continue
        if t.startswith("--file="):
            stdin_file = t.split("=", 1)[1] == "-"; i += 1; continue
        i += 1
    if parts:
        return "\n\n".join(parts)
    if stdin_file:
        return first_heredoc_body(cmd)
    return None


def check(msg):
    lines = msg.rstrip("\n").split("\n")
    # git strips comment lines and trailing blanks; we only see the raw text.
    lines = [l for l in lines if not l.startswith("#")]
    if not lines or not lines[0].strip():
        return
    title = lines[0].rstrip()
    if len(title) > TITLE_MAX:
        deny(f"commit title is {len(title)} chars (max {TITLE_MAX}): {title!r}")
    if len(lines) > 1 and lines[1].strip():
        deny("commit body must be separated from the title by a blank line")
    for n, l in enumerate(lines[2:], start=3):
        if len(l.rstrip()) > BODY_MAX and "://" not in l:
            deny(f"commit body line {n} is {len(l.rstrip())} chars (max {BODY_MAX}): {l.strip()[:60]!r}…")


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return
    data = json.loads(raw)
    if data.get("tool_name") != "Bash":
        return
    cmd = data.get("tool_input", {}).get("command") or ""
    if "git" not in cmd or "commit" not in cmd:
        return
    msg = messages_from_args(cmd)
    if msg is not None:
        check(msg)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        try:
            import traceback
            os.makedirs(os.path.join(WS, ".claude", "logs"), exist_ok=True)
            with open(os.path.join(WS, ".claude", "logs", "hook_errors.log"), "a") as f:
                f.write(traceback.format_exc() + "\n")
        except Exception:
            pass
    sys.exit(0)
