#!/usr/bin/env python3
"""
Summarize .claude/logs/subagents.jsonl written by the SubagentStop hook.

Adds, on top of the original version:
  - cache_read / cache_creation tokens broken out per model and per agent type
  - a rudimentary cost estimate per model/agent, based on published per-token
    rates and standard cache-read/cache-write multipliers
  - all-time totals: "By model" / "By agent type" / the grand totals always
    cover every logged session, not just recent ones
  - a "Last N individual invocations" table showing per-invocation cost and
    token usage, so a single run's numbers are visible on its own line
  - entries with zero recorded tokens (e.g. interim "wait for the results"
    SubagentStop events with no usage data) are skipped everywhere — they
    aren't counted in totals and aren't shown in the invocations table

Usage:
  python3 .claude/scripts/subagent_summary.py                  # all-time totals + last 10 invocations
  python3 .claude/scripts/subagent_summary.py --invocations 25 # show last 25 invocations instead of 10
  python3 .claude/scripts/subagent_summary.py --log path/to/subagents.jsonl
  python3 .claude/scripts/subagent_summary.py --prune          # delete zero-token relic rows from the log

Zero-token relics (what --prune removes, and why they exist):
  Rows whose four token fields are all zero aren't zero-cost runs — they're
  artifacts with no usage data, from two sources: (1) before commit 45b06df the
  hook read the wrong SubagentStop payload field names and logged zeros for
  every run; (2) SubagentStop also fires for interim events (the parent
  checking on a still-running agent) whose transcript has no assistant usage
  yet. The summary always skips them; the hook now skips writing kind (2) at
  the source (while still logging an *unreadable* transcript as zeros, since a
  streak of those is how the 45b06df regression was spotted); `--prune`
  rewrites the log file to drop the relics already accumulated. Lines that
  aren't valid JSON are preserved untouched.

Cost notes (read before trusting the numbers):
  - Rates below are standard published per-million-token rates as of writing.
    They WILL go stale — check platform.claude.com/docs/en/about-claude/pricing
    before relying on this for real budgeting.
  - Cache reads are estimated at 0.1x the model's base input rate (the
    standard ~90% cache-read discount).
  - Cache creation (writes) is estimated at 1.25x the model's base input
    rate, which assumes the default 5-minute cache TTL. If you're using the
    1-hour TTL, real cache-write cost is closer to 2x input rate — this
    script does not distinguish between the two, so treat cache-write cost
    as an approximation, not a bill.
  - Rows where the model is "unknown" (hook couldn't parse the transcript)
    are shown with token totals but no cost, since we don't know the rate
    to apply.
"""
import json
import os
import sys
import argparse
from collections import defaultdict

# (input $/MTok, output $/MTok) — base rates, no cache/batch discount applied
MODEL_RATES = {
    "opus": (5.00, 25.00),
    "sonnet": (3.00, 15.00),
    "haiku": (1.00, 5.00),
}

CACHE_READ_MULTIPLIER = 0.1    # ~90% discount vs base input rate
CACHE_WRITE_MULTIPLIER = 1.25  # 5-minute TTL cache write; 1-hour TTL is ~2x


def rates_for_model(model_name):
    """Match a full model string (e.g. claude-haiku-4-5-20251001) to a rate tier."""
    if not model_name:
        return None
    name = model_name.lower()
    for tier, rates in MODEL_RATES.items():
        if tier in name:
            return rates
    return None


def estimate_cost(input_tok, output_tok, cache_read_tok, cache_creation_tok, model_name):
    rates = rates_for_model(model_name)
    if rates is None:
        return None
    input_rate, output_rate = rates
    cost = (
        (input_tok / 1_000_000) * input_rate
        + (output_tok / 1_000_000) * output_rate
        + (cache_read_tok / 1_000_000) * input_rate * CACHE_READ_MULTIPLIER
        + (cache_creation_tok / 1_000_000) * input_rate * CACHE_WRITE_MULTIPLIER
    )
    return cost


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


def entry_tokens(e):
    """Pull out the token fields for one log entry as a tuple of ints."""
    input_t = e.get("input_tokens", 0) or 0
    output_t = e.get("output_tokens", 0) or 0
    cache_read_t = e.get("cache_read_tokens", 0) or 0
    cache_creation_t = e.get("cache_creation_tokens", 0) or 0
    # "fresh" = uncached input + output; older log lines called this
    # total_tokens (misleading — it excludes the cache fields entirely)
    fresh_t = e.get("fresh_tokens") or e.get("total_tokens") or (input_t + output_t)
    return input_t, output_t, cache_read_t, cache_creation_t, fresh_t


def has_recorded_tokens(input_t, output_t, cache_read_t, cache_creation_t):
    """False for interim/placeholder events (e.g. 'wait for the results') that
    carry no usage data at all — these should be skipped everywhere."""
    return bool(input_t or output_t or cache_read_t or cache_creation_t)


def prune_log(log_path):
    """Rewrite the log in place, dropping parseable zero-token entries.
    Invalid-JSON lines are kept as-is (don't destroy data we don't understand)."""
    if not os.path.exists(log_path):
        print(f"No log file found at {log_path}")
        sys.exit(1)
    kept, dropped = [], 0
    with open(log_path, "r") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                kept.append(raw)
                continue
            if has_recorded_tokens(*entry_tokens(e)[:4]):
                kept.append(raw)
            else:
                dropped += 1
    tmp = log_path + ".tmp"
    with open(tmp, "w") as f:
        f.writelines(kept)
    os.replace(tmp, log_path)
    print(f"Pruned {dropped} zero-token relic row(s); {len(kept)} line(s) kept.")


def fmt(n):
    return f"{n:,}"


def fmt_cost(c):
    return f"${c:.4f}" if c is not None else "n/a"


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


def new_bucket():
    return {
        "runs": 0, "input": 0, "output": 0,
        "cache_read": 0, "cache_creation": 0,
        "fresh": 0, "cost": 0.0, "cost_known": True,
    }


def accumulate(bucket, input_t, output_t, cache_read_t, cache_creation_t, fresh_t, model):
    bucket["runs"] += 1
    bucket["input"] += input_t
    bucket["output"] += output_t
    bucket["cache_read"] += cache_read_t
    bucket["cache_creation"] += cache_creation_t
    bucket["fresh"] += fresh_t
    cost = estimate_cost(input_t, output_t, cache_read_t, cache_creation_t, model)
    if cost is None:
        bucket["cost_known"] = False
    else:
        bucket["cost"] += cost


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", default=".claude/logs/subagents.jsonl")
    parser.add_argument("--invocations", type=int, default=10,
                         help="Show this many of the most recent individual "
                              "invocations (default 10)")
    parser.add_argument("--prune", action="store_true",
                        help="Rewrite the log file, deleting zero-token relic "
                             "entries (see the docstring for what these are)")
    args = parser.parse_args()
    if args.invocations <= 0:
        parser.error("--invocations must be a positive integer")

    if args.prune:
        prune_log(args.log)
        return

    entries = load_entries(args.log)
    if not entries:
        print("Log file is empty — no subagent runs recorded yet.")
        return

    # sort chronologically (timestamps are ISO strings, so lexical sort works)
    entries.sort(key=lambda e: e.get("timestamp", ""))

    total_logged = len(entries)

    # Skip entries with no recorded tokens at all (e.g. interim SubagentStop
    # events like "wait for the results") — they're noise, not zero-cost runs.
    usable = []
    for e in entries:
        input_t, output_t, cache_read_t, cache_creation_t, fresh_t = entry_tokens(e)
        if not has_recorded_tokens(input_t, output_t, cache_read_t, cache_creation_t):
            continue
        usable.append((e, input_t, output_t, cache_read_t, cache_creation_t, fresh_t))

    skipped = total_logged - len(usable)
    if not usable:
        print(f"{total_logged} run(s) logged, but none have recorded token usage.")
        return

    by_model = defaultdict(new_bucket)
    by_agent = defaultdict(new_bucket)

    grand_input = grand_output = grand_cache_read = grand_cache_creation = 0
    grand_cost = 0.0
    grand_cost_known = True

    for e, input_t, output_t, cache_read_t, cache_creation_t, fresh_t in usable:
        model = e.get("model") or "unknown"
        agent = e.get("agent_type") or "unknown"

        accumulate(by_model[model], input_t, output_t, cache_read_t, cache_creation_t, fresh_t, model)
        accumulate(by_agent[agent], input_t, output_t, cache_read_t, cache_creation_t, fresh_t, model)

        grand_input += input_t
        grand_output += output_t
        grand_cache_read += cache_read_t
        grand_cache_creation += cache_creation_t
        cost = estimate_cost(input_t, output_t, cache_read_t, cache_creation_t, model)
        if cost is None:
            grand_cost_known = False
        else:
            grand_cost += cost

    skip_note = f" ({skipped} zero-token entr{'y' if skipped == 1 else 'ies'} skipped)" if skipped else ""
    print(f"All-time totals across {len(usable)} subagent run(s){skip_note}")
    print(
        "\nHow to read this: every agent turn re-sends the whole conversation, so the\n"
        "already-seen prefix piles up as cache reads (~0.1x input rate) and new context as\n"
        "cache writes (~1.25x). 'Fresh' = uncached input + output only — it is neither\n"
        "total work nor cost; the cost column prices all four token kinds."
    )

    model_rows = sorted(
        ([m, s["runs"], fmt(s["input"]), fmt(s["output"]), fmt(s["cache_read"]),
          fmt(s["cache_creation"]), fmt(s["fresh"]),
          fmt_cost(s["cost"]) if s["cost_known"] else "n/a"]
         for m, s in by_model.items()),
        key=lambda r: r[0],
    )
    print_table(
        "By model",
        model_rows,
        ["Model", "Runs", "Input tok", "Output tok", "Cache read", "Cache create", "Fresh tok", "Est. cost"],
    )

    agent_rows = sorted(
        ([a, s["runs"], fmt(s["input"]), fmt(s["output"]), fmt(s["cache_read"]),
          fmt(s["cache_creation"]), fmt(s["fresh"]),
          fmt_cost(s["cost"]) if s["cost_known"] else "n/a"]
         for a, s in by_agent.items()),
        key=lambda r: -int(r[-2].replace(",", "")),
    )
    print_table(
        "By agent type",
        agent_rows,
        ["Agent type", "Runs", "Input tok", "Output tok", "Cache read", "Cache create", "Fresh tok", "Est. cost"],
    )

    print(f"\nGrand totals ({len(usable)} run(s), all-time)")
    print("-" * 50)
    print(f"Input tokens:          {fmt(grand_input)}")
    print(f"Output tokens:         {fmt(grand_output)}")
    print(f"Cache read tokens:     {fmt(grand_cache_read)}")
    print(f"Cache creation tokens: {fmt(grand_cache_creation)}")
    print(f"Fresh (input+output):  {fmt(grand_input + grand_output)}")
    if grand_cost_known:
        print(f"Estimated cost:        {fmt_cost(grand_cost)}")
    else:
        print("Estimated cost:        n/a (one or more runs had an unrecognized model)")
        print("  Note: rows with model 'unknown' are excluded from cost totals above.")

    # Individual invocations — most recent first, zero-token entries already
    # filtered out above.
    recent = list(reversed(usable[-args.invocations:]))
    invocation_rows = [
        [e.get("timestamp", ""), e.get("agent_type") or "unknown", e.get("model") or "unknown",
         fmt(input_t), fmt(output_t), fmt(cache_read_t), fmt(cache_creation_t), fmt(fresh_t),
         fmt_cost(estimate_cost(input_t, output_t, cache_read_t, cache_creation_t, e.get("model")))]
        for e, input_t, output_t, cache_read_t, cache_creation_t, fresh_t in recent
    ]
    print_table(
        f"Last {len(invocation_rows)} individual invocation(s)",
        invocation_rows,
        ["Timestamp", "Agent type", "Model", "Input", "Output", "Cache read", "Cache create", "Fresh", "Cost"],
    )


if __name__ == "__main__":
    main()
