# Launch Dev Server

Start the development server without blocking this chat, and surface its URL.

Usage: `/dev [port]` — e.g. `/dev 5173`. With no argument, use the project's
recorded default port (see step 1a), falling back to stack detection.

## Steps

0. **Detect the environment first.** If `/.dockerenv` exists or
   `$REMOTE_CONTAINERS`/`$DEVCONTAINER` is set, you're in the dev container —
   follow the container path in steps 2–4 (this is the usual case). Otherwise
   use the host path.

1. Detect the dev command and port from the project's stack:
   - **Node** (`package.json`): use `scripts.dev` (or `start`); read port hints,
     default `3000`
   - **Python**: `Makefile` `dev`/`run` target, `manage.py runserver` (Django,
     port `8000`), or `uvicorn`/`flask run` (`8000`/`5000`)
   - **Rust** (`Cargo.toml`): `cargo run`
   - **Go** (`go.mod`): `go run .`
   - **Any** (`Makefile`): prefer a `dev`/`run`/`serve` target
   - If you can't determine the command or port, ask the user.

   a. **Port precedence:** an explicit argument (`/dev 5173`) wins; else a
      `Dev port: <port>` line recorded in the project CLAUDE.md; else the
      stack detection above. Pass the chosen port via the dev command's own
      flag (`next dev -p`, `vite --port`, `uvicorn --port`,
      `manage.py runserver 0.0.0.0:<port>`, `flask run -p`; many servers also
      honor a `PORT` env var) — don't edit config files to change the port.

   b. **First use of a port sets the default.** After the server is confirmed
      up (step 4) on an explicitly requested port that isn't the recorded
      default yet, persist it: add or update the one-liner `Dev port: <port>`
      in the project CLAUDE.md (same pattern as `Commit policy:`), and tell
      the user it's now the default for future `/dev` runs. Never record
      ports that came from detection or from the recorded default itself.

2. **Never launch a second server — check for a running one first.** This
   step is what prevents the spawn-loop failure mode (a new server every few
   seconds, each dying on "port in use").
   - Probe before launching: is something already listening on the chosen
     port (`ss -tlnp 2>/dev/null | grep :<port>` or
     `curl -sf -o /dev/null http://localhost:<port>`), or is a dev-server
     process of this project already alive (check your own background tasks
     first, then `pgrep -af "vite|next|uvicorn|runserver|flask"`)?
   - **If yes: reuse it.** Report the URL of the running server and stop —
     dev servers hot-reload, so edits don't need a restart. Only restart
     (kill first, confirm the port is free, then launch) if the user asked
     for a restart or the change genuinely requires one (env vars, deps,
     server config).
   - **If the port is taken by something else:** say so and ask — don't
     auto-pick another port, and never retry the same launch in a loop. One
     failed launch = stop and diagnose (Error Recovery rule), because each
     retry leaks another background process.

3. **Launch it without blocking this chat.**
   - **In the container:** run the server as a background task (e.g. the Bash
     tool's `run_in_background`), and make it **bind `0.0.0.0`, not
     `127.0.0.1`** — a server bound to localhost inside the container isn't
     reachable from the host and the editor can't forward it. Most frameworks
     take a host flag: `next dev -H 0.0.0.0`, `vite --host`,
     `uvicorn --host 0.0.0.0`, `manage.py runserver 0.0.0.0:8000`,
     `flask run --host 0.0.0.0`. Don't pin a host port or assume one is free —
     the editor auto-forwards the container port to whatever host port is open
     (which may differ), so parallel containers don't collide.
   - **On the host:** open a new terminal window/tab running the dev command so
     it stays up independently (PowerShell: `Start-Process powershell
-ArgumentList '-NoExit','-Command','cd \"PROJECT_PATH\"; DEV_COMMAND'`).

4. Wait ~3 seconds, then surface the URL — **do not open a browser yourself**:
   - **In the container:** there is no host browser, and the host port may not
     match the container port. Tell the user the container port (e.g. `3000`)
     and that the editor auto-forwards it — they open it from VS Code's **Ports**
     panel (or the toast). Don't run `open`/`xdg-open`.
   - **On the host:** you may open it — `open` (macOS) / `xdg-open` (Linux) /
     `Start-Process` (Windows) on `http://localhost:PORT`.

5. Confirm to the user: server is running in the background / a new terminal,
   how to reach it (forwarded port or `http://localhost:PORT`), and that this
   chat stays available.

Keep the chat unblocked. Never run the dev server in the foreground of this session.

---
