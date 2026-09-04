# View Plans

List and open saved plans from Plan Mode.

A plan records decisions (the approach, what was rejected and why, what was
measured). It is **not** the queue: outstanding work lives in
`_planning/STATUS.md`. Checkboxes in a plan are a scratchpad while it is being
executed, so treat the progress counts below as a hint, not the truth — the
tree and STATUS.md are the truth.

## Steps

1. Look for plans in `_planning/plans/`. If the directory doesn't exist or is empty, say "No plans saved yet. Plans are automatically saved here when exiting Plan Mode."

2. List all plan files with a numbered index, showing for each:
   - **#** — selection number
   - **Date** — from filename
   - **Name** — human-readable name from filename
   - **Status** — count completed vs total checkboxes (e.g., "3/7 done", "Complete")

   Example output:
   ```
   # Saved Plans

   | # | Date       | Plan                          | Progress   |
   |---|------------|-------------------------------|------------|
   | 1 | 2026-02-11 | Add user authentication       | 3/7 steps  |
   | 2 | 2026-02-09 | Refactor billing system       | Complete   |
   | 3 | 2026-02-05 | Domain search optimization    | 0/5 steps  |
   ```

3. Ask the user which plan to open by number.

4. When a plan is opened, display its full contents and highlight:
   - Remaining unchecked items (`- [ ]`) as **TODO** — but first check whether
     the plan is stale: commits landed since it was last touched
     (`git log --oneline <last plan commit>..HEAD`) while boxes are still open,
     which is what the `plan-staleness-check` SessionStart hook flags as
     `PLAN_DRIFT`. If so, verify each open box against the tree before calling
     anything TODO; boxes that describe shipped work get ticked, not resumed.
   - Any items that appear blocked or dependent on other work
   - Offer to resume implementation if there are genuinely incomplete steps —
     or, if the plan has gone quiet, to **retire** it: move what survives to
     STATUS.md's Backlog (`update-status` skill), keep the decisions in the
     file or fold them into CHANGELOG, and delete the plan.