- **`sync-harness.sh` no longer overwrites edited files without asking.**
  `.claude/README.md`, `STACKS.md`, `init-firewall.sh`, `initialize.sh` and
  `claude-harness.zsh` were replaced whenever they differed; they now follow
  the mirrored-directory rule (an unedited old copy updates silently, an
  edited one shows its diff and asks). The Dockerfile is replaced above the
  `PROJECT LAYERS` line silently only when that section matches a past
  boilerplate version; layers added above the line (e.g. a Playwright
  install) now trigger a prompt instead of being dropped. Every prompt opens
  with a header naming the file and its diff size, plus a legend for the
  `-`/`+` sides.
