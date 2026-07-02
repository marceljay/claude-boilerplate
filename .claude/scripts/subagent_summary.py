#!/usr/bin/env python3
"""
Summarize .claude/logs/subagents.jsonl written by the SubagentStop hook.

Usage:
  python3 .claude/scripts/subagent_summary.py
  python3 .claude/scripts/subagent_summary.py --log path/to/subagents.jsonl
"""
import json
import os
import sys
import argparse
from collections import defaultdict


def load_entries(log_path):
    if not os.path.exists(log_path):
        print(f"No log file found at {log_path}")
        sys.exit(1)
    entries = []
    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


def fmt(n):
    return f"{n:,}"


def print_table(title, rows, headers):
    print(f"\n{title}")
    print("-" * len(title))
    widths = [max(len(str(h)), *(len(str(r[i])) for r in rows)) if rows else len(str(h))
              for i, h in enumerate(headers)]
    header_line = "  ".join(str(h).ljust(w) for h, w in zip(headers, widths))
    print(header_line)
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print("  ".join(str(v).ljust(w) for v, w in zip(r, widths)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", default=".claude/logs/subagents.jsonl")
    args = parser.parse_args()

    entries = load_entries(args.log)
    if not entries:
        print("Log file is empty — no subagent runs recorded yet.")
        return

    by_model = defaultdict(lambda: {"runs": 0, "input": 0, "output": 0, "total": 0})
    by_agent = defaultdict(lambda: {"runs": 0, "input": 0, "output": 0, "total": 0})

    grand_input = grand_output = grand_cache_read = grand_cache_creation = 0

    for e in entries:
        model = e.get("model") or "unknown"
        agent = e.get("agent_type") or "unknown"
        input_t = e.get("input_tokens", 0) or 0
        output_t = e.get("output_tokens", 0) or 0
        total_t = e.get("total_tokens", input_t + output_t)

        for bucket, key in ((by_model, model), (by_agent, agent)):
            bucket[key]["runs"] += 1
            bucket[key]["input"] += input_t
            bucket[key]["output"] += output_t
            bucket[key]["total"] += total_t

        grand_input += input_t
        grand_output += output_t
        grand_cache_read += e.get("cache_read_tokens", 0) or 0
        grand_cache_creation += e.get("cache_creation_tokens", 0) or 0

    model_rows = sorted(
        ([m, s["runs"], fmt(s["input"]), fmt(s["output"]), fmt(s["total"])]
         for m, s in by_model.items()),
        key=lambda r: r[0],
    )
    print_table("By model", model_rows, ["Model", "Runs", "Input tok", "Output tok", "Total tok"])

    agent_rows = sorted(
        ([a, s["runs"], fmt(s["input"]), fmt(s["output"]), fmt(s["total"])]
         for a, s in by_agent.items()),
        key=lambda r: -int(r[-1].replace(",", "")),
    )
    print_table("By agent type", agent_rows, ["Agent type", "Runs", "Input tok", "Output tok", "Total tok"])

    print(f"\nTotals across {len(entries)} subagent run(s)")
    print("-" * 40)
    print(f"Input tokens:          {fmt(grand_input)}")
    print(f"Output tokens:         {fmt(grand_output)}")
    print(f"Cache read tokens:     {fmt(grand_cache_read)}")
    print(f"Cache creation tokens: {fmt(grand_cache_creation)}")
    print(f"Total (input+output):  {fmt(grand_input + grand_output)}")


if __name__ == "__main__":
    main()