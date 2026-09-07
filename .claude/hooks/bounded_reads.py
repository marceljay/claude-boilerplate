#!/usr/bin/env python3
"""PreToolUse hook: block unbounded `cat` of large files.

Why this exists: every Bash command's stdout lands in the conversation for
good, and it is the largest context cost after the messages themselves. In a
downstream project a single `cat STATUS.md` (65 KB) plus a few whole component
files spent ~80k tokens for maybe 100 lines that were actually needed. The
auto-mode guidance nudges toward Bash reads (`cat`, `sed -n`) and `cat` is
the one that is unbounded — so this hook turns "read a range" from advice
into a rule, the same way block_destructive.py turns "never recursive-force
delete the workspace" into one.

Blocked: a `cat` whose file arguments total more than BOUNDED_READS_MAX_LINES
(default 250) lines or BOUNDED_READS_MAX_BYTES (default 20000) bytes, unless
its output is piped (`cat big | head`, `| grep`, `| jq` ...) — a downstream
consumer is assumed to bound it. The block message tells Claude the file's
size and the bounded forms to use instead.

Not covered: `head -n 5000`, `git show`, `npm audit` tables — those are the
CLAUDE.md "Token Optimization" wording's job. Set BOUNDED_READS=off to
disable. Exit codes and error handling mirror block_destructive.py:
0 = allow, 2 = block; internal errors fail open and log to
.claude/logs/hook_errors.log.
"""

import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from block_destructive import SEP_RE, strip_heredocs, strip_wrappers, tokenize  # noqa: E402

WS = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())


def env_int(name, default):
    try:
        return int(os.environ.get(name) or default)
    except ValueError:
        return default  # a typo in the override must not take the hook down


MAX_LINES = env_int("BOUNDED_READS_MAX_LINES", 250)
MAX_BYTES = env_int("BOUNDED_READS_MAX_BYTES", 20000)


def segments_with_pipe(tokens):
    """Yield (segment, bounded): bounded is True when a `|` or a `>` file
    redirect follows it — a consumer or a file takes the output, not the
    transcript. (`2>&1` is a `>&` token, not a redirect of stdout.)"""
    seg = []
    for t in tokens:
        if SEP_RE.fullmatch(t):
            if seg:
                yield seg, (("|" in t and "||" not in t) or (">" in t and "&" not in t))
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg, False


def resolve_files(args, cwd):
    files = []
    for a in args:
        if a.startswith("-"):  # flags, and `-` meaning stdin
            continue
        p = os.path.expanduser(a)
        if not os.path.isabs(p):
            p = os.path.join(cwd, p)
        matches = glob.glob(p) if any(c in p for c in "*?[") else [p]
        files.extend(m for m in matches if os.path.isfile(m))
    return files


def measure(files):
    lines = size = 0
    for f in files:
        size += os.path.getsize(f)
        with open(f, "rb") as fh:
            lines += sum(1 for _ in fh)
    return lines, size


def check(cmd, cwd):
    try:
        tokens = tokenize(strip_heredocs(cmd))
    except ValueError:
        return  # unparseable — fail open; block_destructive covers the scary cases
    for seg, piped in segments_with_pipe(tokens):
        seg = strip_wrappers(seg)
        if not seg or os.path.basename(seg[0]) != "cat" or piped:
            continue
        files = resolve_files(seg[1:], cwd)
        if not files:
            continue
        lines, size = measure(files)
        if lines <= MAX_LINES and size <= MAX_BYTES:
            continue
        shown = " ".join(a for a in seg[1:] if not a.startswith("-"))
        print(
            f"BLOCKED by .claude/hooks/bounded_reads.py: `cat {shown}` is "
            f"{lines:,} lines / {size / 1024:.1f} KB and would land in context "
            f"whole (limit {MAX_LINES} lines / {MAX_BYTES // 1000} KB). Read a "
            f"range instead: locate with `grep -n PATTERN {shown} | head -20`, "
            f"then `sed -n 'START,ENDp' {shown}` (or `head -60`). Pipe through "
            f"`head`/`grep`/`jq` if you truly need a filtered whole. "
            f"BOUNDED_READS=off disables this hook.",
            file=sys.stderr,
        )
        sys.exit(2)


def main():
    if os.environ.get("BOUNDED_READS", "").lower() in {"off", "0", "false"}:
        return
    raw = sys.stdin.read()
    if not raw.strip():  # run by hand with no input — nothing to judge, not an error
        return
    data = json.loads(raw)
    if data.get("tool_name") != "Bash":
        return
    check(
        data.get("tool_input", {}).get("command") or "",
        data.get("cwd") or os.getcwd(),
    )


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
