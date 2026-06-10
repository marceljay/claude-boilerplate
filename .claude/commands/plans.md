# View Plans

List and open saved plans from Plan Mode.

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
   - Remaining unchecked items (`- [ ]`) as **TODO**
   - Any items that appear blocked or dependent on other work
   - Offer to resume implementation if there are incomplete steps

---

*By [@ds1](https://github.com/ds1) — [boilerplate.md](https://github.com/ds1/boilerplate.md)*