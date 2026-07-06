#!/usr/bin/env python3
"""
Claude Code SubagentStop hook.
Logs every subagent run (task, model, token usage) to .claude/logs/subagents.jsonl
in the project directory.

Install:
  1. Save this file as .claude/hooks/log_subagent.py in your project
  2. chmod +x .claude/hooks/log_subagent.py
  3. Add the hook config below to .claude/settings.json
"""
import json
import os
import sys
import datetime


def extract_text(content):
    """message content can be a plain string or a list of content blocks."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        return " ".join(parts)
    return ""


def log_run(data):
    # Prefer the project dir the harness resolved; fall back to the payload cwd.
    base = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd", ".")
    agent_type = data.get("agent_type", "unknown")
    agent_id = data.get("agent_id", "unknown")
    # SubagentStop-specific fields (Claude Code >= 2.0.42): the subagent's own
    # transcript is `agent_transcript_path`, NOT the bare `transcript_path` (that
    # is the parent session's transcript on Stop/PreToolUse/etc.).
    transcript_path = data.get("agent_transcript_path")
    # Final assistant text, provided directly so we don't have to parse the
    # transcript for the summary (Stop/SubagentStop input field).
    last_message = data.get("last_assistant_message", "")

    model = None
    input_tokens = 0
    output_tokens = 0
    cache_read_tokens = 0
    cache_creation_tokens = 0
    task_prompt = None
    transcript_last_message = ""
    transcript_read = False

    if transcript_path and os.path.exists(transcript_path):
        transcript_read = True
        with open(transcript_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue

                msg = entry.get("message", entry)
                role = msg.get("role")

                # first user message = the task that was delegated
                if role == "user" and task_prompt is None:
                    task_prompt = extract_text(msg.get("content", ""))

                # sum usage across every assistant turn the subagent made; also
                # keep the last non-empty assistant text as a fallback summary in
                # case the payload's `last_assistant_message` was empty.
                if role == "assistant":
                    model = msg.get("model", model)
                    text = extract_text(msg.get("content", ""))
                    if text.strip():
                        transcript_last_message = text
                    usage = msg.get("usage", {})
                    input_tokens += usage.get("input_tokens", 0) or 0
                    output_tokens += usage.get("output_tokens", 0) or 0
                    cache_read_tokens += usage.get("cache_read_input_tokens", 0) or 0
                    cache_creation_tokens += usage.get("cache_creation_input_tokens", 0) or 0

    # prefer the payload's final-message field; fall back to the transcript
    if not last_message:
        last_message = transcript_last_message

    # SubagentStop also fires for interim events (e.g. the parent checking on a
    # still-running agent) whose transcript has no assistant usage yet — those
    # are noise, skip them. But an UNREADABLE transcript still gets logged with
    # zeros on purpose: a run of all-zero rows is exactly the pattern that
    # exposed the payload-field regression fixed in 45b06df — don't hide the
    # next one. (`subagent_summary.py --prune` deletes old zero-token rows.)
    has_usage = input_tokens or output_tokens or cache_read_tokens or cache_creation_tokens
    if transcript_read and not has_usage:
        return

    log_dir = os.path.join(base, ".claude", "logs")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, "subagents.jsonl")

    entry = {
        "timestamp": datetime.datetime.now().isoformat(timespec="seconds"),
        "agent_id": agent_id,
        "agent_type": agent_type,
        "task": (task_prompt or "")[:300],
        "model": model,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "cache_read_tokens": cache_read_tokens,
        "cache_creation_tokens": cache_creation_tokens,
        # Deliberately NOT named total_tokens: this is uncached input + output
        # only. Cache reads/writes (the bulk of most runs' volume and cost) are
        # the two fields above — summing all five is how you'd get "total work".
        "fresh_tokens": input_tokens + output_tokens,
        "result_summary": (last_message or "")[:300],
    }

    with open(log_file, "a") as f:
        f.write(json.dumps(entry) + "\n")


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return  # nothing to do, don't crash the session
    try:
        log_run(data)
    except Exception:
        return  # hooks must fail silent — never break the subagent/session


if __name__ == "__main__":
    main()