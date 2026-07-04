#!/usr/bin/env python3
"""PreToolUse hook: block destructive Bash commands the deny list can't catch.

Why this exists: settings.json `deny` rules are *prefix* matches, so
`Bash(rm -rf:*)` misses `rm -fr` / `rm -r -f`, and `Bash(git push --force:*)`
misses `git push -f`. This hook tokenizes the actual command (quote-aware, so
a commit message that merely *mentions* a dangerous string doesn't trip it)
and blocks the intent, not the spelling. It runs in every permission mode,
including bypassPermissions.

It is defense-in-depth — a tripwire, NOT a sandbox. The devcontainer and its
firewall are the real containment. Known limits: it doesn't chase targets fed
through `xargs`/`find -delete`, and only recurses one level into `bash -c`.

Blocked:
  - rm with recursive+force flags aimed at a protected target: /, ~/$HOME,
    ., .., bare *, any .git, the workspace root itself, or any path outside
    the workspace and /tmp
  - git push --force / -f / --force-with-lease to main or master (explicit
    refspec, or the current branch when none is given)
  - git reset --hard (discards uncommitted work)
  - git clean -f… (deletes untracked files)
  - DROP TABLE/DATABASE/SCHEMA or TRUNCATE TABLE passed to a DB client
  - dd writing to a block device; mkfs

If one of these is genuinely wanted, the user runs it themselves (`! <cmd>`
in the prompt) or edits this hook.

Exit codes: 0 = allow, 2 = block (stderr is fed back to Claude).
Internal errors fail OPEN (exit 0) but are appended to
.claude/logs/hook_errors.log so bugs don't hide as silent blocks.
"""

import json
import os
import re
import shlex
import subprocess
import sys

WS = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
# Newline must be a separator, not whitespace: otherwise a multi-line command
# collapses into one segment and e.g. an `rm` on line 1 "sees" later lines'
# arguments as its targets (found the hard way — false positive on a test
# script). shlex returns runs of punctuation as one token ("&&\n"), so
# separators are matched by character class, not set membership.
SEPARATOR_CHARS = "();<>|&;\n"
SEP_RE = re.compile(r"^[();<>|&\n]+$")
WRAPPERS = {"sudo", "command", "nohup", "time", "timeout", "stdbuf", "env"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
DB_CLIENTS = {"psql", "mysql", "mariadb", "sqlite3", "duckdb", "clickhouse-client"}
SQL_RE = re.compile(r"\b(drop\s+(table|database|schema)|truncate\s+table)\b", re.I)
PROTECTED_BRANCHES = {"main", "master"}


def deny(reason):
    print(
        f"BLOCKED by .claude/hooks/block_destructive.py: {reason}. "
        "If the user genuinely wants this, ask them to run it themselves "
        "(`! <command>` in the prompt) or to adjust this hook.",
        file=sys.stderr,
    )
    sys.exit(2)


def tokenize(cmd):
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=SEPARATOR_CHARS)
    lex.whitespace = " \t\r"  # NOT \n — it must surface as a separator token
    lex.whitespace_split = True
    return list(lex)


def split_segments(tokens):
    seg, segs = [], []
    for t in tokens:
        if SEP_RE.fullmatch(t):
            if seg:
                segs.append(seg)
            seg = []
        else:
            seg.append(t)
    if seg:
        segs.append(seg)
    return segs


def strip_wrappers(seg):
    i = 0
    while i < len(seg):
        t = seg[i]
        if t in WRAPPERS or re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*=.*", t):
            i += 1
            continue
        break
    return seg[i:]


def short_flags(args, letters):
    """True if any short-option token (-abc) contains one of `letters`."""
    return any(
        re.fullmatch(r"-[a-zA-Z]+", a) and any(c in letters for c in a[1:])
        for a in args
    )


def dangerous_rm_target(t):
    if t.startswith("~") or t.startswith("$") or "$HOME" in t:
        return True  # home, or an unresolvable variable — can't verify, so block
    if t in (".", "..", "./", "../", "*"):
        return True
    base = re.split(r"[*?]", t, maxsplit=1)[0]
    if base == "":
        return True  # token started with a wildcard
    p = os.path.realpath(base)  # relative paths resolve against the session cwd
    home = os.path.realpath(os.path.expanduser("~"))
    if p in ("/", WS, home):
        return True
    if os.path.basename(p) == ".git" or f"{os.sep}.git{os.sep}" in p + os.sep:
        return True
    if p.startswith(WS + os.sep) or p.startswith("/tmp" + os.sep):
        return False
    return True  # absolute path outside the workspace and /tmp


def check_rm(args):
    recursive = "--recursive" in args or short_flags(args, "rR")
    force = "--force" in args or short_flags(args, "f")
    if not (recursive and force):
        return
    targets, opts_done = [], False
    for a in args:
        if a == "--":
            opts_done = True
            continue
        if not opts_done and a.startswith("-") and a != "-":
            continue
        if SEP_RE.fullmatch(a):
            continue
        targets.append(a)
    for t in targets:
        if dangerous_rm_target(t):
            deny(f"recursive+force rm aimed at protected path '{t}'")


def current_branch():
    try:
        r = subprocess.run(
            ["git", "symbolic-ref", "--short", "-q", "HEAD"],
            cwd=WS, capture_output=True, text=True, timeout=5,
        )
        return r.stdout.strip() or None
    except Exception:
        return None


def check_git_push(toks):
    forced = any(t == "-f" or t.startswith("--force") for t in toks)
    if not forced:
        return
    i = toks.index("push")
    positionals = [t for t in toks[i + 1:] if not t.startswith("-")]
    refspecs = positionals[1:]  # first positional is the remote
    names = []
    for r in refspecs:
        dest = r.split(":")[-1].lstrip("+")
        names.append(dest.removeprefix("refs/heads/"))
    if not names or "HEAD" in names:
        cur = current_branch()
        if cur is None:
            deny("force-push with undeterminable target branch")
        names.append(cur)
    for n in names:
        if n in PROTECTED_BRANCHES:
            deny(f"force-push to protected branch '{n}'")


def check_git(toks):
    if "push" in toks:
        check_git_push(toks)
    if "reset" in toks and "--hard" in toks:
        deny("`git reset --hard` discards uncommitted work")
    if "clean" in toks and ("--force" in toks or short_flags(toks[1:], "f")):
        deny("`git clean -f` deletes untracked files")


def check_segment(seg, depth):
    seg = strip_wrappers(seg)
    if not seg:
        return
    cmd = os.path.basename(seg[0])
    args = seg[1:]
    if cmd == "rm":
        check_rm(args)
    elif cmd == "git":
        check_git(seg)
    elif cmd in SHELLS and "-c" in args:
        script = args[args.index("-c") + 1] if args.index("-c") + 1 < len(args) else ""
        analyze(script, depth + 1)
    elif cmd == "dd" and any(a.startswith("of=/dev/") for a in args):
        deny("dd writing to a block device")
    elif cmd.startswith("mkfs"):
        deny("mkfs formats a filesystem")
    elif cmd in DB_CLIENTS and SQL_RE.search(" ".join(args)):
        deny(f"destructive SQL passed to {cmd}")


def analyze(cmd, depth=0):
    if depth > 3 or not cmd.strip():
        return
    try:
        tokens = tokenize(cmd)
    except ValueError:
        # Unparseable (unbalanced quotes) — coarse raw-string check only.
        if re.search(
            r"\brm\s+(-\S+\s+)*-[a-zA-Z]*(rf|fr)|git\s+push\s.*(\s-f\b|--force)"
            r"|git\s+reset\s+--hard",
            cmd,
        ):
            deny("destructive pattern in a command I couldn't safely parse")
        return
    for seg in split_segments(tokens):
        check_segment(seg, depth)


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        return
    analyze(data.get("tool_input", {}).get("command") or "")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        # Fail open (don't brick every Bash call on a hook bug), but leave a
        # diagnosable trace — silent excepts are how the last regression hid.
        try:
            import traceback
            os.makedirs(os.path.join(WS, ".claude", "logs"), exist_ok=True)
            with open(os.path.join(WS, ".claude", "logs", "hook_errors.log"), "a") as f:
                f.write(traceback.format_exc() + "\n")
        except Exception:
            pass
    sys.exit(0)
