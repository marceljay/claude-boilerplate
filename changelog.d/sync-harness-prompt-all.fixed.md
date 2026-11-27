- **`sync-harness.sh` asks before every change it makes in a project.**
  Updates to unedited older harness files, the Dockerfile's section above
  the `PROJECT LAYERS` marker, new files, renames, the `CUSTOM.md` stub,
  moving per-project lines out of `CLAUDE.md`, and the recorded
  `.claude/HARNESS_VERSION` used to happen without a question; each now
  shows its diff (or the start of a new file) and asks, default No.
  Answering No to everything leaves the project unchanged. A fresh install
  still asks once for creating files that do not exist yet. Executable
  bits now follow the committed mode, so Markdown files are no longer made
  executable in projects synced from a macOS checkout.
