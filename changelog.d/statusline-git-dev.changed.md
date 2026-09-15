- **Status line shows git position and dev-server state next to `ctx`.**
  `usage-statusline.sh` now appends `branch@sha` of the checked-out commit
  (plus `wt:<name>` inside a linked worktree, `@sha` alone on a detached
  HEAD) and `dev up :<port>` / `dev down`, probing the `Dev port:` recorded
  in `.claude/CUSTOM.md` first, then the common dev ports. Segments degrade
  to being omitted when git, `jq`, or `ss` are unavailable. `/dev` now names
  `CUSTOM.md` as where `Dev port:` lives, matching the other per-project lines.
