#!/usr/bin/env python3
"""PreToolUse hook: route package installs through Socket's scanner.

Why this exists: `.npmrc` (ignore-scripts) and the age gate in
`.devcontainer/STACKS.md` are passive — they stop install-time code execution
and day-zero releases, but neither looks at what a package actually *does*.
Socket does, and its `socket npm|npx|pnpm|yarn` wrappers audit first and then
hand off to the real package manager. Nothing triggers them automatically
though, so a plain `npm install` sails straight past. This hook closes that
gap for commands *Claude* runs: it blocks the unwrapped form and tells Claude
to re-run the wrapped one.

**Inert by default.** The boilerplate does not ship Socket (it needs an API
token — see the /init ask). The hook no-ops unless BOTH are true:
  - a `socket` binary is on PATH
  - SOCKET_CLI_API_TOKEN (or SOCKET_SECURITY_API_KEY) is set
Set SOCKET_HOOK=off to disable it even then. If you authenticate some other
way (`socket login`), export the token too or the hook stays asleep — it
deliberately won't block on a Socket it can't be sure is usable.

Scope and limits — this is a nudge, not a control:
  - Only the four managers Socket wraps: npm, npx, pnpm, yarn. `cargo add`,
    `pip install`, `go get` have no wrapper; use `socket scan create` for
    those (nothing here enforces it).
  - Only commands run through the Bash tool. A `git pull` that changes a
    lockfile, or anything you run yourself in a terminal, is not covered —
    that's a CI concern, see STACKS.md §Active scanning (Socket).
  - It has its own small tokenizer rather than sharing block_destructive.py's,
    so neither hook can break the other. Same shlex approach, less of it.

Exit codes: 0 = allow, 2 = block (stderr is fed back to Claude).
Internal errors fail OPEN (exit 0), logged to .claude/logs/hook_errors.log.
"""

import json
import os
import re
import shlex
import shutil
import sys

SEPARATOR_CHARS = "();<>|&;\n"
SEP_RE = re.compile(r"^[();<>|&\n]+$")
WRAPPERS = {"sudo", "command", "nohup", "time", "timeout", "stdbuf", "env"}

# Subcommands that resolve and fetch packages. Bare `yarn` is an install too;
# bare `npm`/`pnpm` just print help, and `npx` always executes remote code.
FETCHES = {
    "npm": {"install", "i", "add", "ci", "update", "up"},
    "pnpm": {"install", "i", "add", "update", "up", "dlx", "create"},
    "yarn": {"install", "add", "up", "upgrade", ""},
    "npx": None,  # every invocation
}


def enabled():
    if os.environ.get("SOCKET_HOOK", "").lower() in ("off", "0", "false"):
        return False
    if not shutil.which("socket"):
        return False
    return bool(
        os.environ.get("SOCKET_CLI_API_TOKEN")
        or os.environ.get("SOCKET_SECURITY_API_KEY")
    )


def tokenize(cmd):
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=SEPARATOR_CHARS)
    lex.whitespace = " \t\r"  # NOT \n — it must surface as a separator token
    lex.whitespace_split = True
    return list(lex)


def segments(tokens):
    seg, out = [], []
    for t in tokens:
        if SEP_RE.fullmatch(t):
            if seg:
                out.append(seg)
            seg = []
        else:
            seg.append(t)
    if seg:
        out.append(seg)
    return out


def strip_wrappers(seg):
    i = 0
    while i < len(seg):
        t = seg[i]
        if t in WRAPPERS or re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*=.*", t):
            i += 1
            continue
        break
    return seg[i:]


def unwrapped_install(seg):
    """Return the package manager if this segment fetches packages unaudited."""
    seg = strip_wrappers(seg)
    if not seg:
        return None
    cmd = os.path.basename(seg[0])
    # Already audited: `socket npm …`, or the socket-npm/-npx/-pnpm/-yarn bins.
    if cmd == "socket" or cmd.startswith("socket-"):
        return None
    if cmd not in FETCHES:
        return None
    subs = FETCHES[cmd]
    if subs is None:
        return cmd
    # First non-flag argument is the subcommand ("" when there is none).
    sub = next((a for a in seg[1:] if not a.startswith("-")), "")
    return cmd if sub in subs else None


def main():
    raw = sys.stdin.read()
    if not raw.strip():  # run by hand with no input — nothing to judge
        return
    data = json.loads(raw)
    if data.get("tool_name") != "Bash":
        return
    if not enabled():
        return
    command = data.get("tool_input", {}).get("command") or ""
    if not command.strip():
        return
    try:
        segs = segments(tokenize(command))
    except ValueError:
        return  # unparseable (unbalanced quotes) — not worth a false block
    for seg in segs:
        pm = unwrapped_install(seg)
        if pm:
            print(
                f"BLOCKED by .claude/hooks/socket_scan.py: `{pm}` fetches "
                "packages without a supply-chain scan. Re-run the same command "
                f"prefixed with `socket` (e.g. `socket {pm} install <pkg>`) — "
                "it audits the packages, then hands off to the real "
                f"{pm}. If the user genuinely wants the unaudited form, ask "
                "them to run it themselves (`! <command>` in the prompt).",
                file=sys.stderr,
            )
            sys.exit(2)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        # Fail open — a hook bug must never brick installs — but leave a trace.
        try:
            import traceback
            ws = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
            os.makedirs(os.path.join(ws, ".claude", "logs"), exist_ok=True)
            with open(os.path.join(ws, ".claude", "logs", "hook_errors.log"), "a") as f:
                f.write(traceback.format_exc() + "\n")
        except Exception:
            pass
    sys.exit(0)
